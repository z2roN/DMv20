import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

enum LinkState { connecting, open, closed }

/// 상대 한 명과의 WebRTC 직접 연결 (데이터 채널 1개).
///
/// 데이터 채널로 오가는 것:
///  - 글자 프레임(JSON):  {t:'m'} 메시지, {t:'f'} 파일 시작, {t:'e'} 파일 끝,
///                       {t:'w'} 받은 양 알림(흐름 제어), {t:'a'} 잘 받았다는 확인
///  - 바이너리 프레임: 파일 조각 (16KB)
class PeerLink {
  PeerLink({
    required this.peerId,
    required this.sid,
    required this.initiator,
    required this.signal,
  });

  final String peerId;
  final String sid;
  final bool initiator;

  /// 연결 신호(offer/answer/ICE)를 중개 서버로 보내는 함수
  final void Function(Map<String, dynamic> data) signal;
  final DateTime createdAt = DateTime.now();

  LinkState state = LinkState.connecting;
  void Function(LinkState s)? onState;
  void Function(Map<String, dynamic> j)? onJson;
  void Function(Uint8List data)? onBinary;

  RTCPeerConnection? _pc;
  RTCDataChannel? _dc;
  bool _remoteSet = false;
  final List<RTCIceCandidate> _pending = [];
  final Completer<void> _ready = Completer<void>();
  Future<void> _sigChain = Future<void>.value();
  Future<void> _fileChain = Future<void>.value();
  final Map<String, int> _acked = {};

  static const int _chunk = 16 * 1024;
  static const int _window = 1024 * 1024; // 받는 쪽이 확인해 주기 전까지 보낼 수 있는 양

  bool get isOpen => state == LinkState.open && _dc != null;

  void _setState(LinkState s) {
    if (state == s || state == LinkState.closed) return;
    state = s;
    onState?.call(s);
  }

  Future<void> start() async {
    try {
      final pc = await createPeerConnection({
        'iceServers': [
          {
            'urls': [
              'stun:stun.l.google.com:19302',
              'stun:stun1.l.google.com:19302',
            ],
          },
        ],
        'sdpSemantics': 'unified-plan',
      });
      _pc = pc;
      pc.onIceCandidate = (RTCIceCandidate c) {
        if (c.candidate == null) return;
        signal({
          'k': 'ice',
          'c': {
            'candidate': c.candidate,
            'sdpMid': c.sdpMid,
            'sdpMLineIndex': c.sdpMLineIndex,
          },
        });
      };
      pc.onConnectionState = (RTCPeerConnectionState s) {
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            s == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          _setState(LinkState.closed);
        }
      };
      if (initiator) {
        final dc = await pc.createDataChannel('chat', RTCDataChannelInit()..ordered = true);
        _bind(dc);
        final offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        signal({'k': 'offer', 'sdp': offer.sdp, 'type': offer.type});
      } else {
        pc.onDataChannel = (RTCDataChannel dc) => _bind(dc);
      }
    } catch (_) {
      _setState(LinkState.closed);
    } finally {
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  void _bind(RTCDataChannel dc) {
    _dc = dc;
    dc.onDataChannelState = (RTCDataChannelState s) {
      if (s == RTCDataChannelState.RTCDataChannelOpen) {
        _setState(LinkState.open);
      } else if (s == RTCDataChannelState.RTCDataChannelClosed) {
        _setState(LinkState.closed);
      }
    };
    dc.onMessage = (RTCDataChannelMessage m) {
      if (m.isBinary) {
        onBinary?.call(m.binary);
        return;
      }
      try {
        final j = jsonDecode(m.text);
        if (j is! Map<String, dynamic>) return;
        if (j['t'] == 'w') {
          _acked[j['id'] as String] = (j['n'] as num).toInt();
          return;
        }
        onJson?.call(j);
      } catch (_) {}
    };
    if (dc.state == RTCDataChannelState.RTCDataChannelOpen) _setState(LinkState.open);
  }

  /// 중개 서버로 받은 연결 신호 처리 (순서대로 하나씩)
  Future<void> onSignal(Map<String, dynamic> m) {
    _sigChain = _sigChain.then((_) => _handleSignal(m)).catchError((_) {});
    return _sigChain;
  }

  Future<void> _handleSignal(Map<String, dynamic> m) async {
    await _ready.future;
    final pc = _pc;
    if (pc == null) return;
    switch (m['k']) {
      case 'offer':
        await pc.setRemoteDescription(
            RTCSessionDescription(m['sdp'] as String?, m['type'] as String?));
        _remoteSet = true;
        await _flushIce();
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        signal({'k': 'answer', 'sdp': answer.sdp, 'type': answer.type});
      case 'answer':
        await pc.setRemoteDescription(
            RTCSessionDescription(m['sdp'] as String?, m['type'] as String?));
        _remoteSet = true;
        await _flushIce();
      case 'ice':
        final c = m['c'] as Map<String, dynamic>;
        final cand = RTCIceCandidate(
          c['candidate'] as String?,
          c['sdpMid'] as String?,
          (c['sdpMLineIndex'] as num?)?.toInt(),
        );
        if (_remoteSet) {
          await pc.addCandidate(cand);
        } else {
          _pending.add(cand);
        }
    }
  }

  Future<void> _flushIce() async {
    final pc = _pc;
    if (pc == null) return;
    for (final c in _pending) {
      try {
        await pc.addCandidate(c);
      } catch (_) {}
    }
    _pending.clear();
  }

  void sendJson(Map<String, dynamic> j) {
    final dc = _dc;
    if (dc == null || !isOpen) throw StateError('연결되어 있지 않습니다');
    dc.send(RTCDataChannelMessage(jsonEncode(j)));
  }

  /// 파일을 16KB씩 잘라 보낸다. 받는 쪽 확인(흐름 제어)을 기다리며 보내므로 큰 파일도 안전하다.
  /// 여러 파일은 한 번에 하나씩 순서대로 보낸다.
  Future<void> sendFile({
    required String id,
    required String path,
    required String name,
    required int size,
    required bool isImage,
    required int ts,
    required void Function(int sent) onProgress,
  }) {
    final f = _fileChain.catchError((_) {}).then((_) => _sendFileNow(
          id: id,
          path: path,
          name: name,
          size: size,
          isImage: isImage,
          ts: ts,
          onProgress: onProgress,
        ));
    _fileChain = f;
    return f;
  }

  Future<void> _sendFileNow({
    required String id,
    required String path,
    required String name,
    required int size,
    required bool isImage,
    required int ts,
    required void Function(int sent) onProgress,
  }) async {
    final dc = _dc;
    if (dc == null || !isOpen) throw StateError('연결되어 있지 않습니다');
    sendJson({'t': 'f', 'id': id, 'name': name, 'size': size, 'img': isImage, 'ts': ts});
    var sent = 0;
    var lastMove = DateTime.now();
    var lastAck = 0;
    await for (final data in File(path).openRead()) {
      for (var i = 0; i < data.length; i += _chunk) {
        final end = min(i + _chunk, data.length);
        while (sent - (_acked[id] ?? 0) > _window) {
          if (!isOpen) throw StateError('연결이 끊어졌습니다');
          final a = _acked[id] ?? 0;
          if (a != lastAck) {
            lastAck = a;
            lastMove = DateTime.now();
          } else if (DateTime.now().difference(lastMove) > const Duration(seconds: 45)) {
            throw TimeoutException('상대가 응답하지 않습니다');
          }
          await Future<void>.delayed(const Duration(milliseconds: 12));
        }
        if (!isOpen) throw StateError('연결이 끊어졌습니다');
        dc.send(RTCDataChannelMessage.fromBinary(Uint8List.fromList(data.sublist(i, end))));
        sent += end - i;
        onProgress(sent);
      }
    }
    sendJson({'t': 'e', 'id': id});
    _acked.remove(id);
  }

  Future<void> close() async {
    state = LinkState.closed;
    try {
      await _dc?.close();
    } catch (_) {}
    try {
      await _pc?.close();
    } catch (_) {}
    _dc = null;
    _pc = null;
  }
}
