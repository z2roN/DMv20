import 'dart:async';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'group_crypto.dart';

class Broker {
  const Broker(this.host, this.port);
  final String host;
  final int port;
}

/// 공용 중개 서버 (TLS). 앞에서부터 시도하고 실패하면 다음 것으로 넘어간다.
/// 대화 내용은 이 서버를 지나지 않는다 (접속 표시와 연결 신호만, 그것도 암호화되어 지나감).
const List<Broker> kBrokers = [
  Broker('broker.emqx.io', 8883),
  Broker('broker.hivemq.com', 8883),
];

/// 친구 코드 방식 중개.
///
/// 사람마다 "내 코드"에서 만든 자기 전용 구역(z2rd/<내gid>/…)이 있다.
///   p        : 내 접속 표시 (친구들이 구독해서 봄)
///   s        : 나에게 오는 연결 신호 (친구가 내 코드로 암호화해서 보냄)
///   q/<보낸이>: 나에게 온 친구 요청 (보존)
///   a/<보낸이>: 내가 보낸 요청에 대한 수락 알림 (보존)
/// 친구의 코드를 알아야만 그 친구의 구역에 쓰거나 읽을 수 있다.
class Signaling {
  Signaling({
    required this.my,
    required this.selfId,
    required this.onPresence,
    required this.onSignal,
    required this.onRequest,
    required this.onAccept,
    required this.onStatus,
    required this.onConnected,
  });

  final GroupKeys my;
  final String selfId;
  final void Function(Map<String, dynamic> m, String gid) onPresence;
  final void Function(Map<String, dynamic> m) onSignal;
  final void Function(Map<String, dynamic> m) onRequest;
  final void Function(Map<String, dynamic> m) onAccept;
  final void Function(String status, bool ok) onStatus;

  /// 중개 서버에 (다시) 연결되었을 때
  final void Function() onConnected;

  final Map<String, GroupKeys> _friends = {}; // gid -> 친구 키 (접속 표시 감시)
  MqttServerClient? _c;
  bool _stopped = false;
  bool _connecting = false;
  Timer? _retry;
  Timer? _beat;
  String _name = '';
  final String _boot = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  Future<void> _queue = Future<void>.value();

  String get _base => 'z2rd/${my.gid}';
  String get _presTopic => '$_base/p';

  bool get connected => _c?.connectionStatus?.state == MqttConnectionState.connected;

  Future<void> start(String name) async {
    _name = name;
    _stopped = false;
    await _connect();
  }

  void rename(String name) {
    _name = name;
    announce();
  }

  /// 친구의 접속 표시를 보기 시작
  void watch(GroupKeys k) {
    _friends[k.gid] = k;
    if (connected) _c!.subscribe('z2rd/${k.gid}/p', MqttQos.atLeastOnce);
  }

  void unwatch(String gid) {
    _friends.remove(gid);
    if (connected) {
      try {
        _c!.unsubscribe('z2rd/$gid/p');
      } catch (_) {}
    }
  }

  Future<void> _connect() async {
    if (_stopped || _connecting) return;
    _connecting = true;
    try {
      onStatus('중개 서버에 연결 중…', false);
      for (final b in kBrokers) {
        if (_stopped) return;
        final cid = 'z2rd_${selfId}_${DateTime.now().millisecondsSinceEpoch % 100000}';
        final c = MqttServerClient.withPort(b.host, cid, b.port);
        c.secure = true;
        c.keepAlivePeriod = 30;
        c.logging(on: false);
        c.autoReconnect = true;
        c.setProtocolV311();
        c.connectTimeoutPeriod = 8000;
        final will = await my.seal({'id': selfId, 'n': _name, 'off': true});
        c.connectionMessage = MqttConnectMessage()
            .withClientIdentifier(cid)
            .withWillTopic(_presTopic)
            .withWillMessage(will)
            .withWillQos(MqttQos.atLeastOnce)
            .withWillRetain()
            .startClean();
        try {
          await c.connect();
        } catch (_) {
          try {
            c.disconnect();
          } catch (_) {}
          continue;
        }
        if (c.connectionStatus?.state != MqttConnectionState.connected) {
          try {
            c.disconnect();
          } catch (_) {}
          continue;
        }
        _c = c;
        c.onAutoReconnected = () {
          _subscribe();
          announce();
          onStatus('중개 서버 연결됨', true);
          onConnected();
        };
        c.onAutoReconnect = () => onStatus('중개 서버 다시 연결 중…', false);
        c.onDisconnected = () {
          if (_stopped) return;
          onStatus('중개 서버 연결 끊김 (다시 시도합니다)', false);
          _scheduleRetry();
        };
        c.updates?.listen((list) {
          _queue = _queue.then((_) => _handle(list));
        });
        _subscribe();
        await announce();
        _beat?.cancel();
        _beat = Timer.periodic(const Duration(seconds: 90), (_) => announce());
        onStatus('중개 서버 연결됨', true);
        onConnected();
        return;
      }
      onStatus('중개 서버에 연결하지 못했습니다 (인터넷 확인, 곧 다시 시도)', false);
      _scheduleRetry();
    } finally {
      _connecting = false;
    }
  }

  void _scheduleRetry() {
    if (_stopped) return;
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 10), () {
      if (!connected) {
        try {
          _c?.disconnect();
        } catch (_) {}
        _c = null;
        _connect();
      }
    });
  }

  void _subscribe() {
    final c = _c;
    if (c == null) return;
    c.subscribe('$_base/#', MqttQos.atLeastOnce);
    for (final gid in _friends.keys) {
      c.subscribe('z2rd/$gid/p', MqttQos.atLeastOnce);
    }
  }

  Future<void> _handle(List<dynamic>? list) async {
    if (list == null) return;
    for (final m in list) {
      final msg = m.payload;
      if (msg is! MqttPublishMessage) continue;
      final text = MqttPublishPayload.bytesToStringAsString(msg.payload.message);
      if (text.isEmpty) continue; // 보존 메시지 지우기용 빈 메시지
      final parts = (m.topic as String).split('/');
      if (parts.length < 3) continue;
      final gid = parts[1];
      final kind = parts[2];
      final GroupKeys? keys = gid == my.gid ? my : _friends[gid];
      if (keys == null) continue;
      final map = await keys.open(text);
      if (map == null) continue; // 코드가 다른 사람의 메시지 → 무시
      if (kind == 'p') {
        if (gid != my.gid && map['id'] != selfId) onPresence(map, gid);
      } else if (gid == my.gid) {
        if (kind == 's') {
          onSignal(map);
        } else if (kind == 'q') {
          onRequest(map);
        } else if (kind == 'a') {
          onAccept(map);
        }
      }
    }
  }

  void _pubRaw(String topic, String payload, {bool retain = false}) {
    final c = _c;
    if (c == null || !connected) return;
    final b = MqttClientPayloadBuilder()..addString(payload);
    c.publishMessage(topic, MqttQos.atLeastOnce, b.payload!, retain: retain);
  }

  Future<void> _pubTo(
    GroupKeys to,
    String kind,
    Map<String, dynamic> data, {
    bool retain = false,
    String? sub,
  }) async {
    final topic = 'z2rd/${to.gid}/$kind${sub != null ? '/$sub' : ''}';
    _pubRaw(topic, await to.seal({...data, 'from': selfId}), retain: retain);
  }

  /// "나 접속 중" 알림 (보존 메시지: 나중에 접속한 친구도 바로 볼 수 있음)
  Future<void> announce() async {
    _pubRaw(
      _presTopic,
      await my.seal({
        'id': selfId,
        'n': _name,
        'ts': DateTime.now().millisecondsSinceEpoch,
        'b': _boot,
      }),
      retain: true,
    );
  }

  /// 친구에게 연결 신호 (친구의 코드로 암호화해 친구 구역에 씀)
  Future<void> signal(GroupKeys to, Map<String, dynamic> data) => _pubTo(to, 's', data);

  /// 친구 요청 보내기 (상대 구역에 보존)
  Future<void> sendRequest(GroupKeys to, Map<String, dynamic> data) =>
      _pubTo(to, 'q', data, retain: true, sub: selfId);

  /// 요청 수락 알림 보내기 (요청한 사람 구역에 보존)
  Future<void> sendAccept(GroupKeys to, Map<String, dynamic> data) =>
      _pubTo(to, 'a', data, retain: true, sub: selfId);

  /// 보존된 메시지 지우기 (빈 보존 메시지를 쓰면 삭제됨)
  void clearRetained(String gid, String kind, String sub) =>
      _pubRaw('z2rd/$gid/$kind/$sub', '', retain: true);

  Future<void> stop() async {
    _stopped = true;
    _retry?.cancel();
    _beat?.cancel();
    final c = _c;
    _c = null;
    if (c == null) return;
    try {
      if (c.connectionStatus?.state == MqttConnectionState.connected) {
        final off = await my.seal({'id': selfId, 'n': _name, 'off': true});
        final b = MqttClientPayloadBuilder()..addString(off);
        c.publishMessage(_presTopic, MqttQos.atLeastOnce, b.payload!, retain: true);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      c.disconnect();
    } catch (_) {}
  }
}
