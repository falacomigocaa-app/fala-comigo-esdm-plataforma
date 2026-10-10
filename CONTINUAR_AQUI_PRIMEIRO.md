
## Beta controlado — refresh mobile e APK debug — 10/10/2026

A branch de trabalho `work/complete-audit-20261010` foi criada a partir de `coderabbit/audit-and-fix-issues/0959ae64`. O mobile agora renova access/refresh tokens automaticamente em 401 para download de metas e envio da fila offline, com uma única renovação compartilhada entre chamadas concorrentes, retry único, proteção contra logout/login concorrente e preservação da fila em falhas de rede. Foi adicionada cobertura de rotação concorrente e refresh expirado em `test/esdm_aba_test.dart`.

Validação executada com Flutter 3.47.6, Dart 3.13.5 e JDK 17: `flutter pub get --enforce-lockfile`, `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze --no-fatal-infos --no-fatal-warnings` e `flutter test` passaram; a suíte totalizou 133 testes. `flutter build apk --debug --no-shrink` passou e gerou `build/app/outputs/flutter-apk/app-debug.apk` (SHA-256 `b2d1282ead24b5d875dae110ef3bf490810c60db6ad06cb025320854c258ccc2`).

O APK é apropriado para beta com dados sintéticos, não é release assinado para publicação. O app continua dependente de `PORTAL_API_BASE_URL` apontando para uma API acessível pelo aparelho; o valor padrão `127.0.0.1` serve apenas para execução local. Próximos gates: revisão/CI da PR, API de staging persistente, assinatura de produção, MobSF e validação física em celular/tablet.
