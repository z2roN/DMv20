import 'dart:math';

import 'net/group_crypto.dart';

enum MsgKind { text, file, image }

enum MsgStatus { sending, sent, delivered, failed }

String randomId([int bytes = 8]) {
  final r = Random.secure();
  return List<int>.generate(bytes, (_) => r.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

/// 내 코드 만들기 (헷갈리는 글자 제외, 16글자 = 약 79비트)
String generateCode() {
  const chars = 'abcdefghjkmnpqrstuvwxyz23456789';
  final r = Random.secure();
  final c = List.generate(16, (_) => chars[r.nextInt(chars.length)]).join();
  return '${c.substring(0, 4)}-${c.substring(4, 8)}-${c.substring(8, 12)}-${c.substring(12)}';
}

/// 내 정보 (암호화 저장). code = 내 코드 (친구에게 알려 주는 코드)
class Profile {
  Profile({required this.id, required this.name, required this.code});

  final String id;
  String name;
  String code;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'code': code};

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        name: j['name'] as String,
        code: j['code'] as String,
      );
}

/// 코드를 주고받아 수락된 친구
class Member {
  Member({required this.id, required this.name, this.online = false});

  final String id;

  /// 상대가 정한 이름 (상대가 바꾸면 따라서 바뀜)
  String name;

  /// 이 친구의 코드 (이 코드로 친구의 접속 표시를 보고 연결 신호를 보냄)
  String code = '';

  /// 연결 신호용 키 (저장하지 않음)
  GroupKeys? keys;

  /// 내가 붙인 별명 (나에게만 보임, 상대는 모름)
  String alias = '';
  bool online;

  /// 화면에 보이는 이름: 별명이 있으면 "내가정한별명(상대가정한이름)"
  String get label => alias.isEmpty ? name : '$alias($name)';

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'alias': alias, 'code': code};

  factory Member.fromJson(Map<String, dynamic> j) =>
      Member(id: j['id'] as String, name: j['name'] as String)
        ..alias = (j['alias'] as String?) ?? ''
        ..code = (j['code'] as String?) ?? '';
}

/// 받은 친구 요청 (수락/거절 대기)
class FriendReq {
  FriendReq({required this.id, required this.name, required this.code, required this.ts});

  final String id;
  String name;
  final String code;
  final int ts;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'code': code, 'ts': ts};

  factory FriendReq.fromJson(Map<String, dynamic> j) => FriendReq(
        id: j['id'] as String,
        name: j['name'] as String,
        code: j['code'] as String,
        ts: (j['ts'] as num).toInt(),
      );
}

/// 내가 보낸 친구 요청 (상대가 수락할 때까지 대기)
class PendingOut {
  PendingOut({required this.code, this.alias = '', required this.ts});

  final String code;
  final String alias;
  final int ts;

  Map<String, dynamic> toJson() => {'code': code, 'alias': alias, 'ts': ts};

  factory PendingOut.fromJson(Map<String, dynamic> j) => PendingOut(
        code: j['code'] as String,
        alias: (j['alias'] as String?) ?? '',
        ts: (j['ts'] as num).toInt(),
      );
}

class Msg {
  Msg({
    required this.id,
    required this.peerId,
    required this.mine,
    required this.kind,
    required this.ts,
    this.text = '',
    this.fileName = '',
    this.size = 0,
    this.path = '',
    this.status = MsgStatus.sent,
    this.read = true,
  });

  final String id;
  final String peerId;
  final bool mine;
  final MsgKind kind;
  final int ts;
  final String text;
  final String fileName;
  final int size;
  String path;
  MsgStatus status;
  bool read;

  /// 전송/수신 진행률 0~1 (저장하지 않음)
  double progress = 0;

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(ts);

  Map<String, dynamic> toJson() => {
        'id': id,
        'peer': peerId,
        'mine': mine,
        'kind': kind.name,
        'ts': ts,
        'text': text,
        'fn': fileName,
        'size': size,
        'path': path,
        'st': status.name,
        'read': read,
      };

  factory Msg.fromJson(Map<String, dynamic> j) {
    var st = MsgStatus.values.firstWhere(
      (s) => s.name == j['st'],
      orElse: () => MsgStatus.sent,
    );
    // 앱이 꺼질 때 진행 중이던 전송은 실패로 표시
    if (st == MsgStatus.sending) st = MsgStatus.failed;
    return Msg(
      id: j['id'] as String,
      peerId: j['peer'] as String,
      mine: j['mine'] as bool,
      kind: MsgKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => MsgKind.text),
      ts: (j['ts'] as num).toInt(),
      text: j['text'] as String? ?? '',
      fileName: j['fn'] as String? ?? '',
      size: (j['size'] as num?)?.toInt() ?? 0,
      path: j['path'] as String? ?? '',
      status: st,
      read: j['read'] as bool? ?? true,
    );
  }
}

String formatSize(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

bool isImageName(String name) {
  final n = name.toLowerCase();
  return ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'].any(n.endsWith);
}
