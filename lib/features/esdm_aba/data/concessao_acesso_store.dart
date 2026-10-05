import 'package:hive/hive.dart';

import '../domain/models/concessao_acesso_model.dart';
import 'esdm_secure_box_service.dart';

const escolaPerfilAlvo = 'escola';
const especialistaPerfilAlvo = 'especialista_clinica';

class ConcessaoAcessoStore {
  ConcessaoAcessoStore._();

  static Future<Box<ConcessaoAcessoModel>> _box() {
    return EsdmSecureBoxService.openConcessoesBox();
  }

  static Future<List<ConcessaoAcessoModel>> loadAll() async {
    final box = await _box();
    return box.values.toList();
  }

  static Future<void> save(ConcessaoAcessoModel concessao) async {
    final box = await _box();
    await box.put(concessao.id, concessao);
  }

  static Future<ConcessaoAcessoModel?> findActive(String perfilAlvo) async {
    final concessoes = await loadAll();
    for (final concessao in concessoes) {
      final enabled = concessao.permiteLeituraMetas ||
          concessao.permiteEscritaDados;
      if (concessao.perfilAlvo == perfilAlvo &&
          enabled &&
          !concessao.dataExpiracao.isBefore(DateTime.now())) {
        return concessao;
      }
    }
    return null;
  }
}
