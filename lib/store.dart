import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'net/group_crypto.dart';
import 'net/peer_link.dart';
import 'net/signaling.dart';
import 'vault.dart';
import 'version.dart';

/// 파일 받는 중 상태
class _Rx {
  _Rx(this.msg, this.sink, this.total);
  final Msg msg;
  final IOSink sink;
  final int total;
  int got = 0;
  int lastAck = 0;
}

class ChatStore extends ChangeNotifier {
  ChatStore(this.vault);

  final Vault vault;
  Profile? profile;

  /// 수락된 친구 (서로 코드를 주고받은 사람만)
  final Map<String, Member> members = {};

  /// 받은 친구 요청 / 내가 보낸 친구 요청
  final List<FriendReq> reqIn = [];
  final List<PendingOut> reqOut = [];
  final Map<String, List<Msg>> chats = {};

  /// 중개 서버 상태 문구 / 연결 여부
  String status = '';
  bool brokerOk = false;

  /// 친구 자리가 가득 차서 받아들이지 못한 일이 있었는가
  bool overflow = false;

  GroupKeys? _my;
  Signaling? _sig;
  Timer? _maint;
  final Map<String, GroupKeys> _keyCache = {};
  final Map<String, PeerLink> _links = {};
  final Map<String, _Rx> _rx = {}; // peerId -> 받는 중인 파일
  final Map<String, DateTime> _lastTry = {};
  final Map<String, String> _boots = {};
  final Set<String> _pendingAccepts = {};
  Directory get _dir => vault.dir;

  bool get configured => profile != null;

  /// 내 코드 (친구에게 알려 주는 코드)
  String get myCode => profile?.code ?? '';

  Future<GroupKeys> _keysFor(String code) async {
    final n = GroupKeys.normalize(code);
    final hit = _keyCache[n];
    if (hit != null) return hit;
    final k = await GroupKeys.derive(code);
    _keyCache[n] = k;
    return k;
  }

  // ------------------------------------------------------------ 저장/로드

  String _path(String n) => '${_dir.path}${Platform.pathSeparator}$n.enc';

  Future<dynamic> _read(String name) async {
    try {
      final f = File(_path(name));
      if (await f.exists()) return await vault.decryptDecode(await f.readAsBytes());
    } catch (_) {}
    return null;
  }

  Future<void> _write(String name, Object data) async {
    final f = File(_path(name));
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(await vault.encodeEncrypt(data));
    await tmp.rename(f.path);
  }

  Future<void> load() async {
    final p = await _read('profile');
    if (p is Map<String, dynamic>) {
      var prof = Profile.fromJson(p);
      if (p['v'] != 2) {
        // 1.x 버전(모임 코드 방식)에서 올라온 경우: 개인 코드를 새로 만들고 이전 목록은 버린다
        prof = Profile(id: prof.id, name: prof.name, code: generateCode());
        profile = prof;
        await _write('profile', _profileJson());
      } else {
        profile = prof;
      }
    }
    final f = await _read('friends2');
    if (f is Map) {
      for (final e in (f['members'] as List? ?? const [])) {
        final mm = Member.fromJson(e as Map<String, dynamic>);
        if (mm.code.isNotEmpty) members[mm.id] = mm;
      }
      for (final e in (f['in'] as List? ?? const [])) {
        reqIn.add(FriendReq.fromJson(e as Map<String, dynamic>));
      }
      for (final e in (f['out'] as List? ?? const [])) {
        reqOut.add(PendingOut.fromJson(e as Map<String, dynamic>));
      }
    }
    final c = await _read('chats');
    if (c is List) {
      for (final e in c) {
        final msg = Msg.fromJson(e as Map<String, dynamic>);
        if (!members.containsKey(msg.peerId)) continue;
        chats.putIfAbsent(msg.peerId, () => []).add(msg);
      }
    }
    notifyListeners();
  }

  Map<String, dynamic> _profileJson() => {...profile!.toJson(), 'v': 2};

  Timer? _saveTimer;
  bool _chatsDirty = false;
  bool _friendsDirty = false;
  Future<void> _chain = Future<void>.value();

  void _scheduleSave({bool chatsToo = false, bool friendsToo = false}) {
    _chatsDirty = _chatsDirty || chatsToo;
    _friendsDirty = _friendsDirty || friendsToo;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _flush);
  }

  Future<void> _flush() {
    _saveTimer?.cancel();
    _chain = _chain.then((_) async {
      try {
        if (_chatsDirty) {
          _chatsDirty = false;
          await _write('chats', [
            for (final l in chats.values) for (final m in l) m.toJson(),
          ]);
        }
        if (_friendsDirty) {
          _friendsDirty = false;
          await _write('friends2', {
            'members': [for (final m in members.values) m.toJson()],
            'in': [for (final r in reqIn) r.toJson()],
            'out': [for (final o in reqOut) o.toJson()],
          });
        }
      } catch (_) {}
    });
    return _chain;
  }

  // ------------------------------------------------------------ 시작/종료

  /// 처음 설정(이름) 또는 이름 변경. 내 코드는 처음에 한 번 자동으로 만들어진다.
  Future<void> configure({required String name}) async {
    final n = name.trim();
    if (profile == null) {
      profile = Profile(id: randomId(6), name: n, code: generateCode());
      await _write('profile', _profileJson());
      notifyListeners();
      await startNetwork();
    } else {
      profile!.name = n;
      await _write('profile', _profileJson());
      _sig?.rename(n);
      notifyListeners();
    }
  }

  Future<void> startNetwork() async {
    final p = profile;
    if (p == null) return;
    await _stopNetwork();
    status = '준비 중…';
    notifyListeners();
    _my = await _keysFor(p.code);
    await Future.wait(members.values.map((m) async => m.keys = await _keysFor(m.code)));
    final sig = Signaling(
      my: _my!,
      selfId: p.id,
      onPresence: _onPresence,
      onSignal: _onSignal,
      onRequest: _onRequest,
      onAccept: _onAccept,
      onStatus: (s, ok) {
        status = s;
        brokerOk = ok;
        notifyListeners();
      },
      onConnected: _onBrokerUp,
    );
    _sig = sig;
    for (final m in members.values) {
      sig.watch(m.keys!);
    }
    _maint = Timer.periodic(const Duration(seconds: 10), (_) => _maintain());
    await sig.start(p.name);
  }

  /// 중개 서버에 연결될 때마다: 아직 수락되지 않은 내 요청을 다시 보내고, 밀린 수락 알림을 보낸다
  Future<void> _onBrokerUp() async {
    for (final o in List<PendingOut>.of(reqOut)) {
      await _sendRequest(o);
    }
    await _flushAccepts();
  }

  Future<void> _sendRequest(PendingOut o) async {
    final p = profile;
    if (p == null) return;
    final k = await _keysFor(o.code);
    await _sig?.sendRequest(k, {'id': p.id, 'name': p.name, 'code': p.code});
  }

  Future<void> _flushAccepts() async {
    final p = profile;
    if (p == null || _sig == null || !_sig!.connected) return;
    for (final id in _pendingAccepts.toList()) {
      final m = members[id];
      _pendingAccepts.remove(id);
      if (m?.keys == null) continue;
      await _sig!.sendAccept(m!.keys!, {'id': p.id, 'name': p.name, 'code': p.code});
    }
  }

  /// 앱이 다시 앞으로 나왔을 때: 중개 서버 연결이 끊겨 있으면 다시 연결
  Future<void> resume() async {
    if (profile == null) return;
    final s = _sig;
    if (s == null || !s.connected) {
      await startNetwork();
    } else {
      await s.announce();
    }
  }

  Future<void> _stopNetwork() async {
    _maint?.cancel();
    _maint = null;
    for (final l in _links.values) {
      await l.close();
    }
    _links.clear();
    for (final r in _rx.values) {
      try {
        await r.sink.close();
      } catch (_) {}
    }
    _rx.clear();
    await _sig?.stop();
    _sig = null;
    for (final m in members.values) {
      m.online = false;
    }
  }

  /// 잠금: 연결을 끊고 메모리의 데이터를 정리
  Future<void> unload() async {
    await _flush();
    await _stopNetwork();
    profile = null;
    members.clear();
    reqIn.clear();
    reqOut.clear();
    chats.clear();
  }

  /// 모든 친구·대화·내 코드 삭제 후 처음 상태로
  Future<void> resetAll() async {
    await _stopNetwork();
    profile = null;
    members.clear();
    reqIn.clear();
    reqOut.clear();
    chats.clear();
    for (final n in ['profile', 'friends2', 'members', 'chats']) {
      try {
        await File(_path(n)).delete();
      } catch (_) {}
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _maint?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------ 친구 추가/수락

  int get _slots => members.length + reqOut.length + 1; // 나 포함

  /// 친구의 코드를 넣어 요청 보내기. 성공이면 null, 실패 사유가 있으면 문구
  Future<String?> addFriend(String code, {String alias = ''}) async {
    final p = profile;
    if (p == null) return '먼저 내 이름을 설정해 주세요';
    final n = GroupKeys.normalize(code);
    if (n.length < 12) return '코드 형식이 올바르지 않습니다 (예: abcd-efgh-jkmn-pqrs)';
    if (n == GroupKeys.normalize(p.code)) return '내 코드입니다. 친구의 코드를 넣어 주세요';
    if (members.values.any((m) => GroupKeys.normalize(m.code) == n)) return '이미 친구입니다';
    if (reqOut.any((o) => GroupKeys.normalize(o.code) == n)) return '이미 요청을 보냈습니다 (상대의 수락을 기다리는 중)';
    if (_slots >= kMaxMembers) return '친구는 나 포함 최대 $kMaxMembers명까지입니다';
    final o = PendingOut(code: code.trim(), alias: alias.trim(), ts: DateTime.now().millisecondsSinceEpoch);
    reqOut.add(o);
    _scheduleSave(friendsToo: true);
    notifyListeners();
    await _sendRequest(o);
    return null;
  }

  /// 내가 보낸 요청 취소
  Future<void> cancelRequest(PendingOut o) async {
    final k = await _keysFor(o.code);
    _sig?.clearRetained(k.gid, 'q', profile!.id);
    reqOut.remove(o);
    _scheduleSave(friendsToo: true);
    notifyListeners();
  }

  /// 받은 요청 수락
  Future<void> acceptRequest(FriendReq r) async {
    final ok = await _makeFriend(r.id, r.name, r.code, alias: '', sendAck: true);
    _sig?.clearRetained(_my!.gid, 'q', r.id);
    if (ok) reqIn.removeWhere((x) => x.id == r.id);
    _scheduleSave(friendsToo: true);
    notifyListeners();
  }

  /// 받은 요청 거절
  void rejectRequest(FriendReq r) {
    _sig?.clearRetained(_my!.gid, 'q', r.id);
    reqIn.removeWhere((x) => x.id == r.id);
    _scheduleSave(friendsToo: true);
    notifyListeners();
  }

  Future<bool> _makeFriend(String id, String name, String code,
      {required String alias, required bool sendAck}) async {
    if (members.containsKey(id)) return true;
    if (members.length + 1 >= kMaxMembers) {
      overflow = true;
      notifyListeners();
      return false;
    }
    final m = Member(id: id, name: name)
      ..code = code.trim()
      ..alias = alias;
    m.keys = await _keysFor(code);
    members[id] = m;
    _sig?.watch(m.keys!); // 이제부터 이 친구의 접속 표시를 봄
    if (sendAck) {
      _pendingAccepts.add(id);
      _flushAccepts();
    }
    _scheduleSave(friendsToo: true);
    notifyListeners();
    return true;
  }

  Future<void> _onRequest(Map<String, dynamic> m) async {
    final p = profile;
    final id = m['id'] as String?;
    final code = m['code'] as String?;
    if (p == null || id == null || code == null || id == p.id || m['from'] != id) return;
    final n = GroupKeys.normalize(code);
    if (n == GroupKeys.normalize(p.code) || n.length < 12) return;
    final name = (m['name'] as String?) ?? '?';
    // 이미 친구: 수락 알림을 다시 보내 준다 (상대가 놓쳤을 수 있음)
    final ex = members[id];
    if (ex != null) {
      if (GroupKeys.normalize(ex.code) == n) {
        _pendingAccepts.add(id);
        _flushAccepts();
      }
      _sig?.clearRetained(_my!.gid, 'q', id);
      return;
    }
    // 서로 상대의 코드를 넣은 경우: 바로 친구가 됨
    final oi = reqOut.indexWhere((o) => GroupKeys.normalize(o.code) == n);
    if (oi >= 0) {
      final o = reqOut[oi];
      final ok = await _makeFriend(id, name, code, alias: o.alias, sendAck: true);
      if (ok) reqOut.removeAt(oi);
      _sig?.clearRetained(_my!.gid, 'q', id);
      _scheduleSave(friendsToo: true);
      notifyListeners();
      return;
    }
    final ri = reqIn.indexWhere((r) => r.id == id);
    if (ri >= 0) {
      reqIn[ri].name = name;
    } else {
      if (reqIn.length >= 20) return;
      reqIn.add(FriendReq(id: id, name: name, code: code, ts: DateTime.now().millisecondsSinceEpoch));
    }
    _scheduleSave(friendsToo: true);
    notifyListeners();
  }

  Future<void> _onAccept(Map<String, dynamic> m) async {
    final p = profile;
    final id = m['id'] as String?;
    final code = m['code'] as String?;
    if (p == null || id == null || code == null || m['from'] != id) return;
    final n = GroupKeys.normalize(code);
    final oi = reqOut.indexWhere((o) => GroupKeys.normalize(o.code) == n);
    if (oi < 0) {
      if (members.containsKey(id)) _sig?.clearRetained(_my!.gid, 'a', id);
      return;
    }
    final o = reqOut[oi];
    final ok = await _makeFriend(id, (m['name'] as String?) ?? '?', code, alias: o.alias, sendAck: false);
    if (!ok) return;
    reqOut.removeAt(oi);
    _sig?.clearRetained(_my!.gid, 'a', id); // 처리한 수락 알림 지우기
    _sig?.clearRetained((await _keysFor(code)).gid, 'q', p.id); // 내가 보냈던 요청 지우기
    _scheduleSave(friendsToo: true);
    notifyListeners();
  }

  // ------------------------------------------------------------ 친구 목록(접속 상태)

  bool _isInitiator(String peerId) => profile!.id.compareTo(peerId) < 0;

  void _onPresence(Map<String, dynamic> m, String gid) {
    final id = m['id'] as String?;
    if (id == null || profile == null) return;
    final mem = members[id];
    if (mem == null || mem.keys?.gid != gid) return; // 친구가 아니거나 코드가 다름
    final name = (m['n'] as String?) ?? mem.name;
    if (name != mem.name) {
      mem.name = name;
      _scheduleSave(friendsToo: true);
    }
    final off = m['off'] == true;
    mem.online = !off;
    // 상대 앱이 다시 시작되었으면(시작 표시가 바뀜) 예전 연결은 죽은 것이므로 새로 연결
    final boot = m['b'] as String?;
    if (boot != null) {
      final prev = _boots[id];
      _boots[id] = boot;
      if (prev != null && prev != boot) _dropLink(id);
    }
    if (off) {
      _dropLink(id);
    } else {
      _ensureLink(id);
    }
    notifyListeners();
  }

  /// 내가 보는 상대 이름(별명) 바꾸기. 빈 문자열이면 별명 해제. 상대에게는 아무 영향 없음
  void setAlias(String id, String alias) {
    final m = members[id];
    if (m == null) return;
    m.alias = alias.trim();
    _scheduleSave(friendsToo: true);
    notifyListeners();
  }

  /// 친구 삭제 (대화도 이 기기에서 삭제). 다시 친구가 되려면 코드를 다시 주고받아야 함
  void removeMember(String id) {
    final m = members.remove(id);
    if (m?.keys != null) _sig?.unwatch(m!.keys!.gid);
    _dropLink(id);
    chats.remove(id);
    _boots.remove(id);
    _scheduleSave(chatsToo: true, friendsToo: true);
    notifyListeners();
  }

  // ------------------------------------------------------------ 연결

  LinkState linkState(String id) => _links[id]?.state ?? LinkState.closed;
  bool isLinked(String id) => _links[id]?.isOpen ?? false;

  void _dropLink(String id) {
    final l = _links.remove(id);
    if (l != null) {
      l.close();
      _failReceive(id);
    }
  }

  /// 상대가 접속 중인데 직접 연결이 없으면 연결을 시도한다.
  /// id 가 작은 쪽이 먼저 연결을 걸고(offer), 큰 쪽은 "연결해 주세요"(hello)만 보낸다.
  Future<void> _ensureLink(String id, {bool force = false}) async {
    final mem = members[id];
    if (mem == null || !mem.online || profile == null) return;
    final cur = _links[id];
    if (!force && cur != null && cur.state != LinkState.closed) return;
    final last = _lastTry[id];
    if (!force && last != null && DateTime.now().difference(last) < const Duration(seconds: 8)) {
      return;
    }
    _lastTry[id] = DateTime.now();
    if (_isInitiator(id)) {
      await _openLink(id, initiator: true, sid: randomId(4));
    } else if (mem.keys != null) {
      _sig?.signal(mem.keys!, {'k': 'hello'});
    }
  }

  Future<PeerLink> _openLink(String id, {required bool initiator, required String sid}) async {
    _dropLink(id);
    final keys = members[id]?.keys;
    if (keys == null) return PeerLink(peerId: id, sid: sid, initiator: initiator, signal: (_) {});
    late PeerLink link;
    link = PeerLink(
      peerId: id,
      sid: sid,
      initiator: initiator,
      signal: (d) => _sig?.signal(keys, {...d, 'sid': sid}),
    );
    link.onState = (s) {
      if (s == LinkState.closed && identical(_links[id], link)) {
        _links.remove(id);
        _failReceive(id);
      }
      notifyListeners();
    };
    link.onJson = (j) => _onJson(id, j);
    link.onBinary = (b) => _onBinary(id, b);
    _links[id] = link;
    notifyListeners();
    await link.start();
    return link;
  }

  Future<void> _onSignal(Map<String, dynamic> m) async {
    final from = m['from'] as String?;
    if (from == null || profile == null || members[from] == null) return;
    final k = m['k'];
    if (k == 'hello') {
      if (_isInitiator(from) && members[from]!.online) {
        _lastTry[from] = DateTime.now();
        await _openLink(from, initiator: true, sid: randomId(4));
      }
      return;
    }
    final sid = m['sid'] as String?;
    if (sid == null) return;
    if (k == 'offer') {
      if (_isInitiator(from)) return; // 내가 먼저 걸어야 하는 상대 (동시에 걸린 경우)
      members[from]!.online = true;
      final link = await _openLink(from, initiator: false, sid: sid);
      await link.onSignal(m);
      return;
    }
    final link = _links[from];
    if (link == null || link.sid != sid) return;
    await link.onSignal(m);
  }

  void _maintain() {
    for (final mem in members.values) {
      if (!mem.online) continue;
      final l = _links[mem.id];
      if (l == null || l.state == LinkState.closed) {
        _ensureLink(mem.id);
      } else if (l.state == LinkState.connecting &&
          DateTime.now().difference(l.createdAt) > const Duration(seconds: 25)) {
        _ensureLink(mem.id, force: true); // 연결이 너무 오래 걸리면 처음부터 다시
      }
    }
  }

  // ------------------------------------------------------------ 받기

  void _onJson(String peerId, Map<String, dynamic> j) {
    final t = j['t'];
    if (t == 'm') {
      final id = j['id'] as String;
      final list = chats.putIfAbsent(peerId, () => []);
      if (list.any((m) => m.id == id)) return;
      list.add(Msg(
        id: id,
        peerId: peerId,
        mine: false,
        kind: MsgKind.text,
        ts: (j['ts'] as num).toInt(),
        text: j['text'] as String? ?? '',
        read: false,
      ));
      _links[peerId]?.sendJson({'t': 'a', 'id': id});
      _scheduleSave(chatsToo: true);
      notifyListeners();
    } else if (t == 'f') {
      _startReceive(peerId, j);
    } else if (t == 'e') {
      _finishReceive(peerId, j['id'] as String);
    } else if (t == 'a') {
      final id = j['id'] as String;
      for (final m in chats[peerId] ?? const <Msg>[]) {
        if (m.id == id && m.mine) {
          m.status = MsgStatus.delivered;
          _scheduleSave(chatsToo: true);
          notifyListeners();
          break;
        }
      }
    }
  }

  File _fileTarget(String peerId, String id, String name) {
    final d = Directory('${_dir.path}${Platform.pathSeparator}files${Platform.pathSeparator}$peerId');
    d.createSync(recursive: true);
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return File('${d.path}${Platform.pathSeparator}${id}_$safe');
  }

  void _startReceive(String peerId, Map<String, dynamic> j) {
    final id = j['id'] as String;
    final name = (j['name'] as String?) ?? 'file';
    final size = (j['size'] as num?)?.toInt() ?? 0;
    final img = j['img'] == true;
    if (size > kMaxFileBytes) {
      _links[peerId]?.sendJson({'t': 'x', 'id': id});
      return;
    }
    final file = _fileTarget(peerId, id, name);
    final msg = Msg(
      id: id,
      peerId: peerId,
      mine: false,
      kind: img && isImageName(name) ? MsgKind.image : MsgKind.file,
      ts: (j['ts'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      fileName: name,
      size: size,
      path: file.path,
      status: MsgStatus.sending,
      read: false,
    );
    chats.putIfAbsent(peerId, () => []).add(msg);
    _rx[peerId] = _Rx(msg, file.openWrite(), size);
    notifyListeners();
  }

  void _onBinary(String peerId, Uint8List data) {
    final r = _rx[peerId];
    if (r == null) return;
    r.sink.add(data);
    r.got += data.length;
    final double p = r.total == 0 ? 0.0 : (r.got / r.total).clamp(0.0, 1.0).toDouble();
    final changed = (p - r.msg.progress) >= 0.01;
    if (changed) {
      r.msg.progress = p;
      notifyListeners();
    }
    // 256KB 마다 "여기까지 받았다"고 알려 보내는 쪽이 계속 보낼 수 있게 함
    if (r.got - r.lastAck >= 256 * 1024) {
      r.lastAck = r.got;
      try {
        _links[peerId]?.sendJson({'t': 'w', 'id': r.msg.id, 'n': r.got});
      } catch (_) {}
    }
  }

  Future<void> _finishReceive(String peerId, String id) async {
    final r = _rx[peerId];
    if (r == null || r.msg.id != id) return;
    _rx.remove(peerId);
    try {
      await r.sink.flush();
      await r.sink.close();
    } catch (_) {}
    r.msg.progress = 1;
    r.msg.status = r.got == r.total || r.total == 0 ? MsgStatus.delivered : MsgStatus.failed;
    try {
      _links[peerId]?.sendJson({'t': 'a', 'id': id});
    } catch (_) {}
    _scheduleSave(chatsToo: true);
    notifyListeners();
  }

  void _failReceive(String peerId) {
    final r = _rx.remove(peerId);
    if (r == null) return;
    r.sink.close().catchError((_) {});
    r.msg.status = MsgStatus.failed;
    _scheduleSave(chatsToo: true);
    notifyListeners();
  }

  // ------------------------------------------------------------ 보내기

  /// 성공이면 null, 실패 사유가 있으면 문구를 돌려준다
  String? sendText(String peerId, String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final link = _links[peerId];
    if (link == null || !link.isOpen) return '상대와 직접 연결되어 있지 않습니다';
    final msg = Msg(
      id: randomId(8),
      peerId: peerId,
      mine: true,
      kind: MsgKind.text,
      ts: DateTime.now().millisecondsSinceEpoch,
      text: t,
      status: MsgStatus.sending,
    );
    chats.putIfAbsent(peerId, () => []).add(msg);
    try {
      link.sendJson({'t': 'm', 'id': msg.id, 'text': t, 'ts': msg.ts});
      msg.status = MsgStatus.sent;
    } catch (_) {
      msg.status = MsgStatus.failed;
    }
    _scheduleSave(chatsToo: true);
    notifyListeners();
    return null;
  }

  Future<String?> sendFile(String peerId, String path, {bool asImage = false}) async {
    final link = _links[peerId];
    if (link == null || !link.isOpen) return '상대와 직접 연결되어 있지 않습니다';
    final src = File(path);
    if (!await src.exists()) return '파일을 찾을 수 없습니다';
    final size = await src.length();
    if (size > kMaxFileBytes) {
      return '파일이 너무 큽니다 (최대 ${formatSize(kMaxFileBytes)})';
    }
    final name = path.split(RegExp(r'[\\/]')).last;
    final id = randomId(8);
    final img = asImage && isImageName(name);
    var keep = path;
    if (img) {
      // 보낸 이미지는 앱 폴더로 복사해 둔다 (원본을 옮기거나 지워도 대화에서 계속 보이도록)
      try {
        keep = (await src.copy(_fileTarget(peerId, id, name).path)).path;
      } catch (_) {}
    }
    final msg = Msg(
      id: id,
      peerId: peerId,
      mine: true,
      kind: img ? MsgKind.image : MsgKind.file,
      ts: DateTime.now().millisecondsSinceEpoch,
      fileName: name,
      size: size,
      path: keep,
      status: MsgStatus.sending,
    );
    chats.putIfAbsent(peerId, () => []).add(msg);
    notifyListeners();
    try {
      await link.sendFile(
        id: id,
        path: path,
        name: name,
        size: size,
        isImage: img,
        ts: msg.ts,
        onProgress: (sent) {
          final p = size == 0 ? 1.0 : sent / size;
          if (p - msg.progress >= 0.01) {
            msg.progress = p;
            notifyListeners();
          }
        },
      );
      msg.progress = 1;
      if (msg.status == MsgStatus.sending) msg.status = MsgStatus.sent;
    } catch (_) {
      msg.status = MsgStatus.failed;
    }
    _scheduleSave(chatsToo: true);
    notifyListeners();
    return msg.status == MsgStatus.failed ? '파일 전송에 실패했습니다 (연결이 끊어졌을 수 있습니다)' : null;
  }

  // ------------------------------------------------------------ 목록용 조회

  List<Msg> chat(String peerId) => chats[peerId] ?? const <Msg>[];

  Msg? lastOf(String peerId) {
    final l = chats[peerId];
    return (l == null || l.isEmpty) ? null : l.last;
  }

  int unread(String peerId) => chat(peerId).where((m) => !m.mine && !m.read).length;

  int get totalUnread => chats.values.fold(0, (n, l) => n + l.where((m) => !m.mine && !m.read).length);

  void markRead(String peerId) {
    var changed = false;
    for (final m in chat(peerId)) {
      if (!m.mine && !m.read) {
        m.read = true;
        changed = true;
      }
    }
    if (changed) {
      _scheduleSave(chatsToo: true);
      notifyListeners();
    }
  }

  /// 온라인 먼저, 그다음 이름순
  List<Member> get sortedMembers {
    final l = members.values.toList();
    l.sort((a, b) {
      if (a.online != b.online) return a.online ? -1 : 1;
      final la = lastOf(a.id)?.ts ?? 0, lb = lastOf(b.id)?.ts ?? 0;
      if (la != lb) return lb.compareTo(la);
      return a.name.compareTo(b.name);
    });
    return l;
  }

  Future<void> clearChat(String peerId) async {
    chats.remove(peerId);
    _scheduleSave(chatsToo: true);
    notifyListeners();
  }
}
