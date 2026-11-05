import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// 초대 코드 → (암호화 키 32바이트 + 주제 이름용 값 8바이트) 유도. 별도 isolate에서 실행
Future<List<int>> _deriveGroup(String code) async {
  final k = await Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 20000,
    bits: 512,
  ).deriveKeyFromPassword(password: code, nonce: utf8.encode('z2roN_direct-v1'));
  return k.extractBytes();
}

/// 사람마다 "내 코드"가 하나씩 있고, 그 코드를 아는(친구가 된) 사람만 내 접속 표시와 연결 신호를 읽을 수 있다.
/// 중개 서버를 지나가는 모든 신호는 이 코드에서 만든 키로 암호화된다.
/// 중개 서버에는 "암호문"과 코드에서 유도한 임의의 주제 이름만 보인다.
class GroupKeys {
  GroupKeys._(this._key, this.gid);

  final SecretKey _key;

  /// 중개 서버에서 쓰는 주제 이름 (코드에서 유도한 값이라 코드를 모르면 알 수 없음)
  final String gid;
  static final _algo = AesGcm.with256bits();

  static String normalize(String code) => code.replaceAll(RegExp(r'[\s-]+'), '').toLowerCase();

  static Future<GroupKeys> derive(String code) async {
    final bytes = await compute(_deriveGroup, normalize(code));
    final gid = bytes
        .sublist(32, 40)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return GroupKeys._(SecretKey(bytes.sublist(0, 32)), gid);
  }

  Future<String> seal(Map<String, dynamic> m) async {
    final box = await _algo.encrypt(utf8.encode(jsonEncode(m)), secretKey: _key);
    return base64Encode(box.concatenation());
  }

  Future<Map<String, dynamic>?> open(String s) async {
    try {
      final box = SecretBox.fromConcatenation(
        base64Decode(s),
        nonceLength: 12,
        macLength: 16,
      );
      final clear = await _algo.decrypt(box, secretKey: _key);
      final v = jsonDecode(utf8.decode(clear));
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }
}
