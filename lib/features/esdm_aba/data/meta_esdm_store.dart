import 'package:hive/hive.dart';

import '../domain/models/meta_esdm_model.dart';
import 'esdm_secure_box_service.dart';

/// Persistência local cifrada das metas clínicas estruturadas.
class MetaEsdmStore {
  MetaEsdmStore._();

  static Future<Box<MetaEsdmModel>> _box() {
    return EsdmSecureBoxService.openMetasBox();
  }

  static Future<List<MetaEsdmModel>> loadAll() async {
    final box = await _box();
    final metas = box.values.toList();
    metas.sort((left, right) => left.codigoTecnicoDenver.compareTo(
          right.codigoTecnicoDenver,
        ));
    return metas;
  }

  static Future<void> save(MetaEsdmModel meta) async {
    final box = await _box();
    await box.put(meta.id, meta);
  }

  static Future<void> delete(String id) async {
    final box = await _box();
    await box.delete(id);
  }
}
