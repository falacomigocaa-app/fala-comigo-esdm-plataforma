import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

import '../domain/models/concessao_acesso_model.dart';
import '../domain/models/meta_esdm_model.dart';

const concessoesAcessoBoxName = 'concessoes_acesso_box';
const metasEsdmBoxName = 'metas_esdm_box';

/// Abre as boxes ESDM/ABA com uma chave AES-256 exclusiva por box.
///
/// A chave é criada uma única vez, armazenada no cofre seguro da plataforma e
/// nunca é derivada de texto livre ou persistida junto dos dados Hive.
class EsdmSecureBoxService {
  EsdmSecureBoxService._();

  static const _secureStorage = FlutterSecureStorage();
  static const _keyPrefix = 'fala_comigo_esdm_hive_key_';

  static Future<void> deleteEncryptionKeys() async {
    for (final key in (await _secureStorage.readAll()).keys) {
      if (key.startsWith(_keyPrefix)) await _secureStorage.delete(key: key);
    }
  }

  static Future<Box<ConcessaoAcessoModel>> openConcessoesBox() async {
    _registerAdapters();
    return _openBox<ConcessaoAcessoModel>(concessoesAcessoBoxName);
  }

  static Future<Box<MetaEsdmModel>> openMetasBox() async {
    _registerAdapters();
    return _openBox<MetaEsdmModel>(metasEsdmBoxName);
  }

  static Future<Box<T>> _openBox<T>(String boxName) async {
    if (Hive.isBoxOpen(boxName)) return Hive.box<T>(boxName);

    final key = await _getOrCreateKey(boxName);
    return Hive.openBox<T>(
      boxName,
      encryptionCipher: HiveAesCipher(key),
    );
  }

  static void _registerAdapters() {
    if (!Hive.isAdapterRegistered(ConcessaoAcessoModelAdapter().typeId)) {
      Hive.registerAdapter(ConcessaoAcessoModelAdapter());
    }
    if (!Hive.isAdapterRegistered(MetaEsdmModelAdapter().typeId)) {
      Hive.registerAdapter(MetaEsdmModelAdapter());
    }
  }

  static Future<List<int>> _getOrCreateKey(String boxName) async {
    final keyName = '$_keyPrefix$boxName';
    final encoded = await _secureStorage.read(key: keyName);
    if (encoded != null) {
      final key = base64Url.decode(encoded);
      if (key.length != 32) {
        throw StateError('A chave Hive da box "$boxName" não tem 256 bits.');
      }
      return key;
    }

    final key = Hive.generateSecureKey();
    await _secureStorage.write(key: keyName, value: base64UrlEncode(key));
    return key;
  }
}
