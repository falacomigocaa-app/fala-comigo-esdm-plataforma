# Roadmap de correções e continuidade — 07/10/2026

## Objetivo

Este documento reúne os três entregáveis que o próximo agente precisa para continuar sem perder contexto:

1. Patch prioritário para as correções de maior impacto.
2. Checklist por módulo (app, web, backend, CI/CD).
3. Plano de execução para o próximo agente.

---

## 1) Patch prioritário: correções urgentes

### P0-1 — Migração Hive segura e sem perda de dados

Arquivo alvo: `lib/core/services/secure_box_service.dart`

Problema identificado:
- a migração automática de boxes Hive tinha risco de apagar a origem antes de validar a recuperação.
- a proteção atual melhorou, mas a ação definitiva precisa ser uma migração atômica, com backup e rollback explícitos.

Plano de patch:
- implementar `openSecureBoxWithAtomicMigration<T>`;
- criar snapshot do arquivo antes de abrir;
- em caso de erro de abertura, restaurar backup original;
- nunca substituir o arquivo original antes de validar a cópia;
- registrar log de erro por categoria: chave ausente, caixa antiga, corrupção, erro transitório;
- manter `SecureBoxOpenException` com indicação de snapshot restaurado.

Pseudo-código pronto para aplicação:

```dart
static Future<Box<T>> openSecureBoxWithAtomicMigration<T>(
  String name,
) async {
  if (Hive.isBoxOpen(name)) return Hive.box<T>(name);

  final key = await _getOrCreateEncryptionKey(name);
  final snapshot = await _HiveFileSnapshot.capture(_hiveDirectoryPath, name);
  Box<T>? openedBox;

  try {
    openedBox = await Hive.openBox<T>(
      name,
      encryptionCipher: HiveAesCipher(key),
    );

    if (snapshot != null && await snapshot.wasChangedByOpen()) {
      await openedBox.close();
      throw StateError(
        'A caixa foi alterada durante a abertura; rollback obrigatório.',
      );
    }

    await snapshot?.discard();
    return openedBox;
  } catch (error) {
    if (Hive.isBoxOpen(name)) {
      try {
        await Hive.box<T>(name).close();
      } catch (_) {}
    }

    try {
      await snapshot?.restore();
    } catch (restoreError) {
      throw SecureBoxOpenException(
        name,
        StateError(
          'Falha ao abrir: $error. Falha ao restaurar backup: $restoreError',
        ),
      );
    }

    throw SecureBoxOpenException(
      name,
      error,
      nativeSnapshotRestored: snapshot != null,
    );
  }
}
```

Teste mínimo:
- box cifrada legada sem chave não deve destruir arquivos;
- box corrupta deve restaurar snapshot;
- atualização com chave correta deve preservar os dados;
- operação deve falhar fed-back sem apagar a caixa original.

Branch sugerida:
- `fix/atomic-hive-migration`

---

### P0-2 — Limpeza de previews e materialização de mídia em `finally`

Arquivo alvo: `lib/core/services/media_storage_service_io.dart`

Problema identificado:
- a materialização de arquivo em preview é um risco se o chamador não liberar no `finally`.
- há melhoria em `releaseMaterializedFile`, mas a correção definitiva precisa cobrir todos os fluxos.

Plano de patch:
- criar helper `materializeForReadingWithLease(path)`;
- retornar objeto com `File previewPath` + `release()`;
- toda chamada deve liberar no `finally`;
- limpar previews órfãos no startup;
- garantir que a pasta temp do app seja usada somente para preview e nunca para armazenamento durável.

Pseudo-código pronto para aplicação:

```dart
class MaterializedPreviewLease {
  MaterializedPreviewLease({
    required this.file,
    required this.previewDir,
  });

  final File file;
  final Directory previewDir;

  Future<void> release() async {
    if (await file.exists()) await file.delete();
    if (await previewDir.exists()) {
      final files = await previewDir.list().toList();
      if (files.isEmpty) await previewDir.delete(recursive: false);
    }
  }
}

Future<MaterializedPreviewLease> materializeForReadingWithLease(
  String path,
) async {
  final plainBytes = await readBytesForDisplay(path);
  final previewDir = await _previewDirectory();
  await previewDir.create(recursive: true);
  final preview = File(
    '${previewDir.path}/${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32).toRadixString(16)}.bin',
  );
  await preview.writeAsBytes(plainBytes, flush: true);
  return MaterializedPreviewLease(file: preview, previewDir: previewDir);
}
```

Uso obrigatório:

```dart
final lease = await MediaStorageService.materializeForReadingWithLease(path);
try {
  // usar o preview
} finally {
  await lease.release();
}
```

Teste mínimo:
- preview liberado após `finally`;
- preview não deixa arquivo persistente;
- startup limpa órfãos;
- path fora da área privada não é aceito.

Branch sugerida:
- `fix/media-materialization-lease`

---

### P0-3 — Web sem `dart:io` alcançável

Arquivo alvo: `lib/features/parental_area/presentation/screens/transition_alert_edit_screen.dart`

Problema identificado:
- há caminhos nativos de gravação/alerta que não devem ser acessíveis em Web.
- a correção precisa garantir que o código do navegador nunca acesse `dart:io` ou diretório temporário.

Plano de patch:
- impedir que o fluxo de gravação e agendamento apareça em Web;
- usar `if (kIsWeb)` para desabilitar o botão e exibir mensagem explícita;
- separar service de áudio para IO e Web, se houver necessidade de suporte futuro.

Patch recomendado:

```dart
if (kIsWeb) {
  return const Padding(
    padding: EdgeInsets.only(bottom: 8),
    child: Text(
      'Gravação de voz e notificações agendadas não estão habilitadas na prévia Web.',
      style: TextStyle(color: Colors.deepOrange),
    ),
  );
}
```

No futuro, opcional:
- criar `alert_recording_service.dart` com implementação IO e Web;
- remover qualquer referência direta a `dart:io` do fluxo de UI.

Branch sugerida:
- `fix/web-portable-alerts`

---

### P0-4 — Testes críticos de segurança no backend

Arquivo alvo: novo arquivo `portal-api/test/critical-security.test.js`

Problema identificado:
- backend tem autenticação e autorização fortes, mas ainda faltam testes de concorrência e regressão.

Testes prioritários:
- token expirado + requisições paralelas;
- refresh token usado duas vezes;
- consentimento expirado bloqueando POST;
- envelope E2EE com organization mismatch;
- grant revogado bloqueando acesso.

Branch sugerida:
- `test/security-regression-suite`

---

## 2) Checklist por módulo

### App Flutter

- [ ] `lib/core/services/secure_box_service.dart`
  - [ ] tratar backup/rollback em migração
  - [ ] bloquear conversão destrutiva da box original
  - [ ] validar snapshot restaurado

- [ ] `lib/core/services/media_storage_service_io.dart`
  - [ ] `finally` em todas as materializações
  - [ ] limpar previews órfãos
  - [ ] path ownership validation

- [ ] `lib/main.dart`
  - [ ] aplicar orientação saved preference
  - [ ] limpar stale previews no bootstrap
  - [ ] validar expiração de sessão em lifecycle

- [ ] `lib/features/parental_area/presentation/screens/care_coordination_screen.dart`
  - [ ] carregar planos ao abrir
  - [ ] recarregar após salvar/editar

- [ ] `lib/features/parental_area/presentation/screens/transition_alert_edit_screen.dart`
  - [ ] Web sem gravação
  - [ ] sem `dart:io` acessível

- [ ] `lib/core/services/data_wipe_service.dart`
  - [ ] limpar mesmo se notificação falhar
  - [ ] idempotente

### Web

- [ ] proteger paths de mídia personalizada em browser
- [ ] desabilitar gravação de áudio em Web
- [ ] não permitir acesso a `dart:io` em UI
- [ ] validar build com `flutter build web --release`
- [ ] verificar deep-link e base href no destino real

### Backend (`portal-api`)

- [ ] `refresh token rotation` validada
- [ ] `org mismatch` bloqueado
- [ ] `consent expired/revoked` bloqueado
- [ ] `requestId` idempotente
- [ ] 401 com `renewalRequired` em token expirado

### CI/CD

- [ ] pin de actions por SHA
- [ ] `flutter pub get --enforce-lockfile`
- [ ] remover `:latest` do MobSF
- [ ] verificar `flutter analyze` + `flutter test` + `flutter build web`

---

## 3) Plano de execução para o próximo agente

### Ordem de execução

1. Corrigir P0-1: Hive
2. Corrigir P0-2: mídia
3. Corrigir P0-3: Web
4. Criar P0-4: testes críticos do backend
5. Fechar P1-1 a P1-7
6. Validar em Android e Web
7. Preparar AAB/APK/PR final

### Branches sugeridas

- `fix/atomic-hive-migration`
- `fix/media-materialization-lease`
- `fix/web-portable-alerts`
- `test/security-regression-suite`
- `fix/app-orientation-preference`
- `fix/communication-plan-persistence`
- `fix/resource-error-handling`
- `fix/parental-session-enforcement`
- `fix/wipe-idempotent`
- `fix/web-disable-media-flows`
- `ci/reproducible-builds`

### Critérios de aceitação

- [ ] sem perda de dados em migração Hive
- [ ] sem arquivos temporários persisting após preview
- [ ] sem `dart:io` no caminho Web
- [ ] backend com testes críticos verdes
- [ ] app e web mantendo UX funcional sem crash
- [ ] CI reproduzível e com lockfile exigido

### Comandos mínimos para validar

```bash
cd portal-api
npm test

cd ..
flutter test
flutter build web --release
```

Se o ambiente local não tiver Flutter ou Node instalados, registrar a limitação e rodar a validação no CI/GitHub Actions, sem afirmar que tudo passou localmente.

---

## 4) Texto pronto para colar em continuidade

"O projeto foi auditado em app, web e backend. Os principais bloqueadores são migração Hive destrutiva, materialização de mídia sem cleanup, Web com `dart:io` alcançável, ausência de testes críticos de segurança no backend e ausência de enforcement de sessão. A correção deve seguir a ordem: P0-1 a P0-4 primeiro, depois P1-1 a P1-7, depois validações em device/web e build final. Não aprovar release nem piloto com dados reais antes de fechar esses pontos."

---

## 5) Observação final

Este documento não substitui a leitura das auditorias em `docs/auditoria/2026-09-29/`. Ele funciona como guia operacional curto, focado na priorização e na execução do próximo agente.
