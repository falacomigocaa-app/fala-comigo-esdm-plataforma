import 'dart:convert';
import 'dart:async';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Criptografia dos dados clínicos antes de qualquer persistência/transmissão.
class CryptoService {
  CryptoService._();

  static const _storage = FlutterSecureStorage();
  static const _keyPrefix = 'fala_comigo_org_e2ee_key_';
  static final _algorithm = AesGcm.with256bits();

  static final Map<String, Future<void>> _keyOperations = {};
  static Future<T> _withKeyLock<T>(
      String id, Future<T> Function() operation) async {
    final previous = _keyOperations[id] ?? Future<void>.value();
    final completion = Completer<void>();
    _keyOperations[id] = completion.future;
    await previous;
    try {
      return await operation();
    } finally {
      completion.complete();
      if (identical(_keyOperations[id], completion.future)) {
        _keyOperations.remove(id);
      }
    }
  }

  /// Preserva a chave anterior para recuperar envelopes locais já enfileirados.
  static Future<void> importOrganizationKey(
          String organizationId, String encoded) =>
      _withKeyLock(organizationId,
          () => _importOrganizationKey(organizationId, encoded));

  static Future<void> _importOrganizationKey(
      String organizationId, String encoded) async {
    final bytes = base64Decode(encoded);
    if (organizationId.trim().isEmpty || bytes.length != 32) {
      throw const FormatException('Chave provisionada inválida.');
    }
    final key = _storageKey(organizationId);
    final previous = await _storage.read(key: key);
    if (previous != null && previous != encoded) {
      final saved = await _storage.read(key: '${key}_previous');
      final history = saved == null
          ? <String>[]
          : List<String>.from(jsonDecode(saved) as List);
      if (!history.contains(previous)) history.add(previous);
      await _storage.write(key: '${key}_previous', value: jsonEncode(history));
    }
    await _storage.write(key: key, value: base64Encode(bytes));
    await _storage.write(key: '${key}_provisioned', value: 'true');
  }

  static Future<bool> hasProvisionedKey(String organizationId) async =>
      await _storage.read(key: '${_storageKey(organizationId)}_provisioned') ==
      'true';

  static Future<void> clearAllOrganizationKeys() async {
    for (final key in (await _storage.readAll()).keys) {
      if (key.startsWith(_keyPrefix)) await _storage.delete(key: key);
    }
  }

  static Future<String> encryptPayload({
    required String organizationId,
    required String plaintext,
  }) async {
    final keyBytes = await _readOrCreateKey(organizationId);
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

  static Future<String> prepareForUpload(String envelopeJson) async {
    final envelope = jsonDecode(envelopeJson) as Map<String, dynamic>;
    final organizationId = envelope['organizationId'] as String;
    if (!await hasProvisionedKey(organizationId)) {
      throw StateError('Chave provisionada ausente.');
    }
    final bytes = base64Decode(envelope['encryptedData'] as String);
    final key = await _readOrCreateKey(organizationId, create: false);
    try {
      await _algorithm.decrypt(
          SecretBox(bytes.sublist(0, bytes.length - 16),
              nonce: base64Decode(envelope['iv'] as String),
              mac: Mac(bytes.sublist(bytes.length - 16))),
          secretKey: SecretKey(key));
      return envelopeJson; // O mesmo request-id conserva exatamente o mesmo payload.
    } on SecretBoxAuthenticationError {
      return encryptPayload(
          organizationId: organizationId,
          plaintext: await decryptPayload(envelopeJson));
    }
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
    final keyBytes = await _readOrCreateKey(organizationId, create: false);
    final secretBox = SecretBox(
      encryptedData.sublist(0, encryptedData.length - 16),
      nonce: nonce,
      mac: Mac(encryptedData.sublist(encryptedData.length - 16)),
    );
    final saved =
        await _storage.read(key: '${_storageKey(organizationId)}_previous');
    final keys = <List<int>>[keyBytes];
    if (saved != null) {
      keys.addAll((jsonDecode(saved) as List).cast<String>().map(base64Decode));
    }
    for (final candidate in keys) {
      try {
        final clearText = await _algorithm.decrypt(secretBox,
            secretKey: SecretKey(candidate));
        return utf8.decode(clearText);
      } on SecretBoxAuthenticationError {
        // Uma chave antiga só é tentada para leitura/recuperação local.
      }
    }
    throw SecretBoxAuthenticationError();
  }

  static bool isEnvelope(Map<String, dynamic> value) {
    return value['organizationId'] is String &&
        (value['organizationId'] as String).isNotEmpty &&
        value['encryptedData'] is String &&
        (value['encryptedData'] as String).isNotEmpty &&
        value['iv'] is String &&
        (value['iv'] as String).isNotEmpty;
  }

  static Future<void> clearOrganizationKey(String organizationId) =>
      _withKeyLock(organizationId, () async {
        final key = _storageKey(organizationId);
        await _storage.delete(key: key);
        await _storage.delete(key: '${key}_previous');
        await _storage.delete(key: '${key}_provisioned');
      });

  static Future<List<int>> _readOrCreateKey(String organizationId,
          {bool create = true}) =>
      _withKeyLock(organizationId,
          () => _readOrCreateKeyUnlocked(organizationId, create: create));

  static Future<List<int>> _readOrCreateKeyUnlocked(
    String organizationId, {
    bool create = true,
  }) async {
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
    if (!create) {
      throw StateError('Chave E2EE ausente para a organização.');
    }
    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    await _storage.write(
        key: _storageKey(normalized), value: base64Encode(bytes));
    return bytes;
  }

  static String _storageKey(String organizationId) {
    final safeId = base64UrlEncode(utf8.encode(organizationId));
    return '$_keyPrefix$safeId';
  }
}
