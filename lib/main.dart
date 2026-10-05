import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'core/services/media_storage_service.dart';
import 'core/services/transition_alert_service.dart';
import 'core/services/app_orientation_service.dart';
import 'core/services/secure_box_service.dart';
import 'core/services/parental_session_service.dart';
import 'core/services/tts_service.dart';
import 'core/theme/app_theme.dart';
import 'features/aac_grid/data/providers/cards_provider.dart';
import 'features/aac_grid/data/providers/seed_cards.dart';
import 'features/aac_grid/domain/models/pictogram_card.dart';
import 'features/esdm_aba/domain/models/coleta_escola_model.dart';
import 'features/esdm_aba/domain/models/concessao_acesso_model.dart';
import 'features/esdm_aba/domain/models/meta_esdm_model.dart';
import 'features/esdm_aba/domain/models/sincronizacao_queue_model.dart';
import 'features/esdm_aba/presentation/screens/painel_consentimento_screen.dart';
import 'features/esdm_aba/presentation/screens/coleta_escola_screen.dart';
import 'features/esdm_aba/presentation/screens/metas_esdm_screen.dart';
import 'features/esdm_aba/presentation/screens/esdm_dashboard_screen.dart';
import 'features/onboarding/presentation/screens/splash_screen.dart';
import 'features/parental_area/presentation/screens/parental_gate_screen.dart';
import 'features/transition_alerts/data/providers/transition_alerts_provider.dart';
import 'features/transition_alerts/domain/models/transition_alert.dart';
import 'features/transition_alerts/presentation/screens/transition_alert_full_screen.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: CaaApp()));
}

Future<void> _bootstrap() async {
  if (!kIsWeb) {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    SecureBoxService.configureHiveDirectory(documentsDirectory.path);
    await SecureBoxService.recoverPendingHiveSnapshots();
  }
  await Hive.initFlutter();
  await MediaStorageService.clearStalePreviews();
  if (!Hive.isAdapterRegistered(PictogramCardAdapter().typeId)) {
    Hive.registerAdapter(PictogramCardAdapter());
  }
  if (!Hive.isAdapterRegistered(ConcessaoAcessoModelAdapter().typeId)) {
    Hive.registerAdapter(ConcessaoAcessoModelAdapter());
  }
  if (!Hive.isAdapterRegistered(MetaEsdmModelAdapter().typeId)) {
    Hive.registerAdapter(MetaEsdmModelAdapter());
  }
  if (!Hive.isAdapterRegistered(ColetaEscolaModelAdapter().typeId)) {
    Hive.registerAdapter(ColetaEscolaModelAdapter());
  }
  if (!Hive.isAdapterRegistered(SincronizacaoQueueModelAdapter().typeId)) {
    Hive.registerAdapter(SincronizacaoQueueModelAdapter());
  }

  final box = await SecureBoxService.openSecureBox<PictogramCard>(
    cardsBoxName,
  );
  await SecureBoxService.openSecureBox<dynamic>('app_settings');
  try {
    await AppOrientationService.applyChildOrientation();
  } catch (_) {
    // A preferência visual não pode impedir o primeiro uso.
  }
  await SecureBoxService.openSecureBox(transitionAlertsBoxName);

  if (box.isEmpty) {
    for (final card in SeedCards.defaultCards()) {
      await box.put(card.id, card);
    }
  }

  _configureAlertHandler();
}

void _configureAlertHandler() {
  TransitionAlertService.instance.setAlertHandler((alertId) {
    final ctx = navigatorKey.currentContext;
    try {
      final alertsBox = Hive.box(transitionAlertsBoxName);
      final rawMap = alertsBox.get(alertId);
      if (rawMap != null) {
        final alert = TransitionAlert.fromMap(
          Map<String, dynamic>.from(rawMap as Map),
        );
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => TransitionAlertFullScreen(alert: alert),
          ),
        );
      } else if (ctx != null) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir este alerta.')),
        );
      }
    } catch (_) {
      if (ctx != null) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir este alerta.')),
        );
      }
    }
  });
}

Future<void> _initializeOptionalServices() async {
  try {
    await TtsService.instance.init();
  } catch (_) {
    // O serviço tenta inicializar novamente quando for usado.
  }
  try {
    await TransitionAlertService.instance.init();
  } catch (_) {
    // Alertas permanecem indisponíveis nesta plataforma/configuração.
  }
}

class CaaApp extends StatefulWidget {
  const CaaApp({super.key});

  @override
  State<CaaApp> createState() => _CaaAppState();
}

class _CaaAppState extends State<CaaApp> with WidgetsBindingObserver {
  bool _wasInBackground = false;
  late Future<void> _bootstrapFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ParentalSessionService.onExpired = _showParentalGate;
    _bootstrapFuture = _bootstrap();
  }

  @override
  void dispose() {
    if (ParentalSessionService.onExpired == _showParentalGate) {
      ParentalSessionService.onExpired = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _retryBootstrap() {
    setState(() => _bootstrapFuture = _bootstrap());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasInBackground = ParentalSessionService.isAuthenticated;
      ParentalSessionService.lock();
    } else if (state == AppLifecycleState.resumed && _wasInBackground) {
      _wasInBackground = false;
      _showParentalGate();
    }
  }

  void _showParentalGate() {
    final navigator = navigatorKey.currentState;
    if (navigator == null || !mounted) return;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ParentalGateScreen()),
      (route) => route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Fala Comigo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routes: {
        '/coleta-escola': (_) => const ColetaEscolaScreen(),
        '/painel-consentimento': (_) => const PainelConsentimentoScreen(),
        '/metas-esdm': (_) => const MetasEsdmScreen(),
        '/esdm-dashboard': (_) => const EsdmDashboardScreen(),
      },
      home: FutureBuilder<void>(
        future: _bootstrapFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _BootstrapError(onRetry: _retryBootstrap);
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const _BootstrapLoading();
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _initializeOptionalServices();
          });
          return const SplashScreen();
        },
      ),
    );
  }
}

class _BootstrapLoading extends StatelessWidget {
  const _BootstrapLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Preparando a comunicação…'),
          ],
        ),
      ),
    );
  }
}

class _BootstrapError extends StatelessWidget {
  final VoidCallback onRetry;

  const _BootstrapError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: AppTheme.primary,
              ),
              const SizedBox(height: 16),
              const Text(
                'Não foi possível preparar os dados locais.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Não desinstale o app nem use “Limpar dados” enquanto o erro '
                'persistir. Tente novamente; se continuar, preserve o aparelho '
                'e procure o suporte do projeto.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
