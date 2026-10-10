import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Criptografia dos dados clínicos antes de qualquer persistência/transmissão.
class CryptoService {
  CryptoService._();

  static const _storage = FlutterSecureStorage();
  static const _keyPrefix = 'fala_comigo_org_e2ee_key_';
  static final _algorithm = AesGcm.with256bits();

  static Future<String> encryptPayload({
    required String organizationId,
    required String plaintext,
  }) async {
    final keyBytes = await _readKey(organizationId);
    final secretBox = await _algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: SecretKey(keyBytes),
    );
    final encryptedData = base64Encode([
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
    return jsonEncode({
      'organizationId': organizationId,
      'encryptedData': encryptedData,
      'iv': base64Encode(secretBox.nonce),
    });
  }

  static Future<String> decryptPayload(String envelopeJson) async {
    final envelope = jsonDecode(envelopeJson);
    if (envelope is! Map<String, dynamic> || !isEnvelope(envelope)) {
      throw const FormatException('Envelope E2EE inválido.');
    }
    final organizationId = envelope['organizationId'] as String;
    final encryptedData = base64Decode(envelope['encryptedData'] as String);
    final nonce = base64Decode(envelope['iv'] as String);
    if (encryptedData.length <= 16 || nonce.isEmpty) {
      throw const FormatException('Conteúdo E2EE incompleto.');
    }
    final keyBytes = await _readKey(organizationId);
    final secretBox = SecretBox(
      encryptedData.sublist(0, encryptedData.length - 16),
      nonce: nonce,
      mac: Mac(encryptedData.sublist(encryptedData.length - 16)),
    );
    final clearText = await _algorithm.decrypt(
      secretBox,
      secretKey: SecretKey(keyBytes),
    );
    return utf8.decode(clearText);
  }

  static bool isEnvelope(Map<String, dynamic> value) {
    return value['organizationId'] is String &&
        (value['organizationId'] as String).isNotEmpty &&
        value['encryptedData'] is String &&
        (value['encryptedData'] as String).isNotEmpty &&
        value['iv'] is String &&
        (value['iv'] as String).isNotEmpty;
  }

  static Future<void> clearOrganizationKey(String organizationId) {
    return _storage.delete(key: _storageKey(organizationId));
  }

  /// Installs the authenticated server key without replacing a key that may
  /// still protect pending local envelopes.
  static Future<void> saveOrganizationKey({
    required String organizationId,
    required String encodedKey,
  }) async {
    final normalized = organizationId.trim();
    final bytes = base64Decode(encodedKey);
    if (normalized.isEmpty || bytes.length != 32) {
      throw const FormatException('Chave E2EE da organização inválida.');
    }
    final existing = await _storage.read(key: _storageKey(normalized));
    final canonical = base64Encode(bytes);
    if (existing != null && base64Encode(base64Decode(existing)) != canonical) {
      throw StateError(
        'A chave da organização mudou. Preserve as coletas locais antes de migrar a chave.',
      );
    }
    await _storage.write(key: _storageKey(normalized), value: canonical);
  }

  static Future<bool> hasOrganizationKey(String organizationId) async {
    final stored = await _storage.read(key: _storageKey(organizationId.trim()));
    return stored != null && stored.isNotEmpty;
  }

  static Future<void> clearAllOrganizationKeys() async {
    final values = await _storage.readAll();
    for (final key in values.keys.where((key) => key.startsWith(_keyPrefix))) {
      await _storage.delete(key: key);
    }
  }

  static Future<List<int>> _readKey(String organizationId) async {
    final normalized = organizationId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        organizationId,
        'organizationId',
        'Organization ID não pode ser vazio.',
      );
    }
    final stored = await _storage.read(key: _storageKey(normalized));
    if (stored != null && stored.isNotEmpty) {
      final bytes = base64Decode(stored);
      if (bytes.length == 32) return bytes;
      throw const FormatException('Chave E2EE da organização inválida.');
    }
    throw StateError('Chave E2EE ausente para a organização.');
  }

  static String _storageKey(String organizationId) {
    final safeId = base64UrlEncode(utf8.encode(organizationId));
    return '$_keyPrefix$safeId';
  }
}
