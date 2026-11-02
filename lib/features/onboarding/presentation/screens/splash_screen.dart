import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/auth_token_service.dart';
import '../../../aac_grid/presentation/screens/aac_grid_screen.dart';
import '../../../auth/presentation/screens/login_screen.dart';

/// Tela de abertura do app, exibida por um curto período antes da
/// grade principal.
///
/// Segue as mesmas boas práticas de UI/UX para autismo do resto do
/// app: transição suave (fade), sem movimentos bruscos, cores
/// pastel e curta duração para não atrasar o uso.
class SplashScreen extends StatefulWidget {
  final Widget destination;

  const SplashScreen({super.key, this.destination = const AACGridScreen()});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

/// Decide o destino após a abertura sem armazenar a senha do usuário.
/// Se houver sessão persistida, mantém o usuário no app; caso contrário,
/// solicita o primeiro login online.
class SessionLandingScreen extends StatefulWidget {
  const SessionLandingScreen({super.key});

  @override
  State<SessionLandingScreen> createState() => _SessionLandingScreenState();
}

class _SessionLandingScreenState extends State<SessionLandingScreen> {
  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final accessToken = await AuthTokenService.readToken();
    var authenticated = accessToken?.trim().isNotEmpty == true;
    if (!authenticated && await AuthTokenService.readRefreshToken() != null) {
      authenticated = await AuthTokenService.refreshAccessToken();
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => authenticated ? const AACGridScreen() : const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(child: CircularProgressIndicator()),
      );
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();

    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 500),
            pageBuilder: (_, animation, __) =>
                FadeTransition(opacity: animation, child: widget.destination),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chat_bubble_outline,
                  size: 48,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Fala Comigo',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Comunicação Alternativa',
                style: TextStyle(fontSize: 15, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
