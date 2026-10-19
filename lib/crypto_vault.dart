import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CryptoVault {
  static const _keyName = 'mawed.data-key.v1';
  final FlutterSecureStorage storage;
  final AesGcm _cipher = AesGcm.with256bits();
  SecretKey? _key;
  CryptoVault({FlutterSecureStorage? storage}) : storage = storage ?? const FlutterSecureStorage();

  Future<SecretKey> _getKey() async {
    if (_key != null) return _key!;
    final saved = await storage.read(key: _keyName);
    if (saved != null) {
      _key = SecretKey(base64Url.decode(saved));
      return _key!;
    }
    final generated = await _cipher.newSecretKey();
    final bytes = await generated.extractBytes();
    await storage.write(key: _keyName, value: base64UrlEncode(bytes));
    _key = SecretKey(bytes);
    return _key!;
  }

  Future<String> encrypt(String value) async {
    final box = await _cipher.encrypt(utf8.encode(value), secretKey: await _getKey());
    return 'v1:${base64UrlEncode(Uint8List.fromList([...box.nonce, ...box.cipherText, ...box.mac.bytes]))}';
  }

  Future<String?> decrypt(String? encoded) async {
    if (encoded == null) return null;
    if (!encoded.startsWith('v1:')) return encoded; // one-time migration from legacy plaintext rows
    try {
      final bytes = base64Url.decode(encoded.substring(3));
      if (bytes.length < 28) throw const FormatException('ciphertext too short');
      final nonce = bytes.sublist(0, 12);
      final mac = Mac(bytes.sublist(bytes.length - 16));
      final ciphertext = bytes.sublist(12, bytes.length - 16);
      final clear = await _cipher.decrypt(SecretBox(ciphertext, nonce: nonce, mac: mac), secretKey: await _getKey());
      return utf8.decode(clear);
    } catch (_) {
      throw const FormatException('تعذر التحقق من البيانات المشفرة');
    }
  }

  Future<void> destroy() async {
    _key = null;
    await storage.delete(key: _keyName);
  }
}
