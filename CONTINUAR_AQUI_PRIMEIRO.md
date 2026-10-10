
## Correção do novo cartão pela câmera — 10/10/2026

Corrigido o fluxo de criação de cartão personalizado pela câmera. A causa era o `didChangeAppLifecycleState` do `main.dart`: a pausa temporária causada pela Activity da câmera era interpretada como saída da Área Parental, bloqueando a sessão e reabrindo o PIN no retorno. `ParentalSessionService` agora marca atividades externas temporárias; o ciclo de vida não bloqueia a sessão durante câmera/seletor, mas mantém o bloqueio normal quando o app realmente vai para segundo plano. O rascunho e a recuperação do `image_picker` continuam ativos.

Validação: `flutter analyze` sem issues, teste focado da sessão parental passou com 5 testes e suíte Flutter passou com 137 testes. APK debug atualizado gerado com a API beta configurada: `build/app/outputs/flutter-apk/app-debug.apk`, SHA-256 `423a4211f79fa62c92b71500e65d3483a520746949ff55ae09499e5379434663`. Aviso existente não bloqueador do Flutter sobre migração futura para Built-in Kotlin/KGP permanece.
