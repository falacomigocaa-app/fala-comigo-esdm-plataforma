import 'package:hive/hive.dart';

import '../../../core/services/secure_box_service.dart';
import '../domain/models/coleta_escola_model.dart';

const coletaEscolaBoxName = 'coleta_escola_box';
const _legacyColetaEscolaBoxName = 'coleta_escola';

/// Acesso local às coletas escolares, sem depender de rede ou conta.
class ColetaEscolaStore {
  ColetaEscolaStore._();

  static Future<Box<ColetaEscolaModel>> _box() async {
    if (!Hive.isAdapterRegistered(12)) {
      Hive.registerAdapter(ColetaEscolaModelAdapter());
    }
    if (Hive.isBoxOpen(coletaEscolaBoxName)) {
      return Hive.box<ColetaEscolaModel>(coletaEscolaBoxName);
    }
    return SecureBoxService.openSecureBox<ColetaEscolaModel>(
      coletaEscolaBoxName,
    );
  }

  static Future<void> save(ColetaEscolaModel coleta) async {
    final box = await _box();
    await box.put(coleta.id, coleta);
  }

  static Future<List<ColetaEscolaModel>> loadAll() async {
    final box = await _box();
    final records = box.values.toList();
    // Mantém leitura compatível com a primeira versão local da feature,
    // que usava "coleta_escola" antes do contrato "coleta_escola_box".
    final legacyBox = await SecureBoxService.openSecureBox<ColetaEscolaModel>(
      _legacyColetaEscolaBoxName,
    );
    records.addAll(legacyBox.values);
    records
        .sort((left, right) => right.dataRegistro.compareTo(left.dataRegistro));
    return records;
  }
}
