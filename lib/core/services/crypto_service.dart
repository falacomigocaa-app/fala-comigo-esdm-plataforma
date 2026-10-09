import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Criptografia dos dados clínicos antes de qualquer persistência/transmissão.
/// A chave distribuída pelo portal fica no Keychain/Keystore; o servidor recebe
/// apenas envelopes E2EE e nunca a chave em claro.
class CryptoService {
  CryptoService._();

  static const _storage = FlutterSecureStorage();
  static const _keyPrefix = 'fala_comigo_org_e2ee_key_';
  static const _currentVersionPrefix = 'fala_comigo_org_e2ee_current_version_';
  static final _algorithm = AesGcm.with256bits();

  static Future<void> saveOrganizationKey({
    required String organizationId,
    required int keyVersion,
    required String organizationKeyBase64,
  }) async {
    if (keyVersion < 1) throw ArgumentError.value(keyVersion, 'keyVersion');
    final key = base64Decode(organizationKeyBase64);
    if (key.length != 32) throw const FormatException('Chave E2EE inválida.');
    final normalized = _normalizeOrganizationId(organizationId);
    await _storage.write(
      key: _versionedStorageKey(normalized, keyVersion),
      value: base64Encode(key),
    );
    await _storage.write(
      key: _currentVersionStorageKey(normalized),
      value: '$keyVersion',
    );
  }

  static Future<String> encryptPayload({
    required String organizationId,
    required String plaintext,
  }) async {
    final normalized = _normalizeOrganizationId(organizationId);
    final material = await _readOrCreateKey(normalized);
    final secretBox = await _algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: SecretKey(material.key),
    );
    final encryptedData = base64Encode([
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
    return jsonEncode({
      'organizationId': normalized,
      'keyVersion': material.version,
      'encryptedData': encryptedData,
      'iv': base64Encode(secretBox.nonce),
    });
  }

  static Future<String> decryptPayload(String envelopeJson) async {
    final envelope = jsonDecode(envelopeJson);
    if (envelope is! Map<String, dynamic> || !isEnvelope(envelope)) {
      throw const FormatException('Envelope E2EE inválido.');
    }
    final organizationId = _normalizeOrganizationId(envelope['organizationId'] as String);
    final encryptedData = base64Decode(envelope['encryptedData'] as String);
    final nonce = base64Decode(envelope['iv'] as String);
    if (encryptedData.length <= 16 || nonce.isEmpty) {
      throw const FormatException('Conteúdo E2EE incompleto.');
    }
    final requestedVersion = envelope['keyVersion'] is int
        ? envelope['keyVersion'] as int
        : await _readCurrentVersion(organizationId);
    final keyBytes = await _readVersionedKey(organizationId, requestedVersion);
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

  static Future<void> clearOrganizationKey(String organizationId) async {
    final normalized = _normalizeOrganizationId(organizationId);
    final prefix = '${_legacyStorageKey(normalized)}_v';
    final all = await _storage.readAll();
    for (final key in all.keys) {
      if (key == _legacyStorageKey(normalized) || key.startsWith(prefix)) {
        await _storage.delete(key: key);
      }
    }
    await _storage.delete(key: _currentVersionStorageKey(normalized));
  }

  static Future<_KeyMaterial> _readOrCreateKey(String organizationId) async {
    final currentVersion = await _readCurrentVersion(organizationId);
    if (currentVersion != null) {
      return _KeyMaterial(
        currentVersion,
        await _readVersionedKey(organizationId, currentVersion),
      );
    }
    final legacy = await _storage.read(key: _legacyStorageKey(organizationId));
    if (legacy != null && legacy.isNotEmpty) {
      final key = base64Url.decode(legacy);
      if (key.length == 32) return _KeyMaterial(0, key);
    }
    final key = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    await _storage.write(key: _legacyStorageKey(organizationId), value: base64UrlEncode(key));
    return _KeyMaterial(0, key);
  }

  static Future<List<int>> _readVersionedKey(String organizationId, int version) async {
    if (version < 1) {
      final legacy = await _storage.read(key: _legacyStorageKey(organizationId));
      if (legacy == null) throw StateError('Chave E2EE ausente para a organização.');
      return base64Url.decode(legacy);
    }
    final stored = await _storage.read(key: _versionedStorageKey(organizationId, version));
    if (stored == null || stored.isEmpty) {
      throw StateError('Chave E2EE versão $version ausente para a organização.');
    }
    final key = base64Decode(stored);
    if (key.length != 32) throw const FormatException('Chave E2EE inválida.');
    return key;
  }

  static Future<int?> _readCurrentVersion(String organizationId) async {
    final value = await _storage.read(key: _currentVersionStorageKey(organizationId));
    return int.tryParse(value ?? '');
  }

  static String _normalizeOrganizationId(String organizationId) {
    final normalized = organizationId.trim();
    if (normalized.isEmpty) throw ArgumentError.value(organizationId, 'organizationId');
    return normalized;
  }

  static String _safeId(String organizationId) => base64UrlEncode(utf8.encode(organizationId));
  static String _legacyStorageKey(String organizationId) => '$_keyPrefix${_safeId(organizationId)}';
  static String _versionedStorageKey(String organizationId, int version) => '${_legacyStorageKey(organizationId)}_v$version';
  static String _currentVersionStorageKey(String organizationId) => '$_currentVersionPrefix${_safeId(organizationId)}';
}

class _KeyMaterial {
  const _KeyMaterial(this.version, this.key);
  final int version;
  final List<int> key;
}
