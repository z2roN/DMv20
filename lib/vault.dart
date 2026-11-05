import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

const int _kIterations = 100000;

/// 암호 → 키 유도 (UI가 멈추지 않도록 별도 isolate에서 실행)
Future<List<int>> _deriveIsolate(List<Object> a) async {
  final k = await Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: a[2] as int,
    bits: 256,
  ).deriveKeyFromPassword(password: a[0] as String, nonce: a[1] as List<int>);
  return k.extractBytes();
}

/// JSON 직렬화 + AES-GCM 암호화 (UI가 멈추지 않도록 별도 isolate에서 실행)
Future<List<int>> _encodeEncryptIsolate(List<Object> a) async {
  final key = SecretKey(a[0] as List<int>);
  final plain = utf8.encode(jsonEncode(a[1]));
  final box = await AesGcm.with256bits().encrypt(plain, secretKey: key);
  return box.concatenation();
}

/// AES-GCM 복호화 + JSON 해석 (별도 isolate)
Future<Object?> _decryptDecodeIsolate(List<Object> a) async {
  final key = SecretKey(a[0] as List<int>);
  final box = SecretBox.fromConcatenation(
    a[1] as List<int>,
    nonceLength: 12,
    macLength: 16,
  );
  final clear = await AesGcm.with256bits().decrypt(box, secretKey: key);
  return jsonDecode(utf8.decode(clear));
}

/// 앱 암호 + 로컬 데이터 암호화 (AES-256-GCM, 키는 PBKDF2로 암호에서 유도)
///
/// - 초대 코드와 대화 내용이 암호화되어 저장된다.
/// - "자동 로그인"을 켜면 유도된 키를 OS 보안 저장소(Windows DPAPI / Android Keystore)에
///   보관해 다음 실행 때 암호 입력을 생략한다.
class Vault {
  static const _secureKey = 'z2rondirect_vault_key_v1';
  static const _check = 'z2rondirect-ok';

  final _algo = AesGcm.with256bits();
  final _secure = const FlutterSecureStorage();
  late Directory dir;
  SecretKey? _key;

  bool get unlocked => _key != null;

  Future<void> init() async {
    dir = await getApplicationSupportDirectory();
  }

  File get _meta => File('${dir.path}${Platform.pathSeparator}vault.json');

  bool get exists => _meta.existsSync();

  Uint8List _randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
  }

  Future<SecretKey> _derive(String pw, List<int> salt, int iter) async {
    final bytes = await compute(_deriveIsolate, <Object>[pw, salt, iter]);
    return SecretKey(bytes);
  }

  /// 처음 실행: 암호를 만들고 저장소를 초기화
  Future<void> setup(String password, {required bool autoLogin}) async {
    final salt = _randomBytes(16);
    final key = await _derive(password, salt, _kIterations);
    final check = await _encrypt(key, utf8.encode(_check));
    await _meta.writeAsString(jsonEncode({
      'v': 1,
      'iter': _kIterations,
      'salt': base64Encode(salt),
      'check': base64Encode(check),
    }));
    _key = key;
    await _applyAutoLogin(autoLogin);
  }

  /// 암호로 열기. 틀리면 false
  Future<bool> unlock(String password, {required bool autoLogin}) async {
    final meta = jsonDecode(await _meta.readAsString()) as Map<String, dynamic>;
    final key = await _derive(
      password,
      base64Decode(meta['salt'] as String),
      meta['iter'] as int,
    );
    if (!await _verify(key, meta)) return false;
    _key = key;
    await _applyAutoLogin(autoLogin);
    return true;
  }

  /// 저장된 키로 자동 로그인. 실패하면 false
  Future<bool> tryAutoUnlock() async {
    try {
      final stored = await _secure.read(key: _secureKey);
      if (stored == null) return false;
      final meta = jsonDecode(await _meta.readAsString()) as Map<String, dynamic>;
      final key = SecretKey(base64Decode(stored));
      if (!await _verify(key, meta)) return false;
      _key = key;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _verify(SecretKey key, Map<String, dynamic> meta) async {
    try {
      final plain = await _decrypt(key, base64Decode(meta['check'] as String));
      return utf8.decode(plain) == _check;
    } catch (_) {
      return false;
    }
  }

  Future<void> _applyAutoLogin(bool on) async {
    try {
      if (on) {
        final bytes = await _key!.extractBytes();
        await _secure.write(key: _secureKey, value: base64Encode(bytes));
      } else {
        await _secure.delete(key: _secureKey);
      }
    } catch (_) {}
  }

  /// 잠금(로그아웃): 메모리의 키를 지우고 자동 로그인도 해제
  Future<void> lock() async {
    _key = null;
    try {
      await _secure.delete(key: _secureKey);
    } catch (_) {}
  }

  /// 암호를 잊었을 때: 저장된 모든 데이터를 지우고 처음 상태로
  Future<void> reset() async {
    _key = null;
    try {
      await _secure.delete(key: _secureKey);
    } catch (_) {}
    for (final f in dir.listSync()) {
      try {
        f.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  // ------------------------------------------------------------ 파일 암호화

  Future<Uint8List> _encrypt(SecretKey key, List<int> plain) async {
    final box = await _algo.encrypt(plain, secretKey: key);
    return Uint8List.fromList(box.concatenation());
  }

  Future<List<int>> _decrypt(SecretKey key, List<int> data) {
    final box = SecretBox.fromConcatenation(
      data,
      nonceLength: 12,
      macLength: 16,
    );
    return _algo.decrypt(box, secretKey: key);
  }

  Future<Uint8List> encryptBytes(List<int> plain) => _encrypt(_key!, plain);

  /// 데이터를 JSON으로 만들어 암호화한다 (무거운 작업은 백그라운드에서)
  Future<Uint8List> encodeEncrypt(Object data) async {
    final keyBytes = await _key!.extractBytes();
    final out = await compute(_encodeEncryptIsolate, <Object>[keyBytes, data]);
    return Uint8List.fromList(out);
  }

  /// 암호화된 파일 내용을 복호화해서 JSON 객체로 돌려준다 (백그라운드)
  Future<Object?> decryptDecode(List<int> data) async {
    final keyBytes = await _key!.extractBytes();
    return compute(_decryptDecodeIsolate, <Object>[keyBytes, data]);
  }

  Future<List<int>> decryptBytes(List<int> data) => _decrypt(_key!, data);
}
