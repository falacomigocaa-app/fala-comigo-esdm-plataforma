import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/app_orientation_service.dart';
import '../../../../core/services/parental_pin_service.dart';
import '../../../../core/services/parental_session_service.dart';
import '../../../../core/theme/app_theme.dart';
import 'parental_area_transition_screen.dart';
import 'settings_screen.dart';

/// Gate da Área do Responsável. No primeiro uso exige que o responsável crie
/// um PIN próprio; depois aplica verificação e bloqueio progressivo.
class ParentalGateScreen extends StatefulWidget {
  final Widget destination;

  const ParentalGateScreen({
    super.key,
    this.destination = const SettingsScreen(),
  });

  @override
  State<ParentalGateScreen> createState() => _ParentalGateScreenState();
}

class _ParentalGateScreenState extends State<ParentalGateScreen> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _loading = true;
  bool _setupMode = false;
  bool _authenticated = false;
  bool _isBlocked = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    AppOrientationService.applyParentalPinOrientation();
    _loadState();
  }

  Future<void> _loadState() async {
    final hasPin = await ParentalPinService.hasPin();
    if (!mounted) return;
    setState(() {
      _setupMode = !hasPin;
      _loading = false;
    });
  }

  @override
  void dispose() {
    if (!_authenticated) {
      AppOrientationService.applyChildOrientation();
    }
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_setupMode) {
      if (_pinController.text != _confirmController.text) {
        setState(() => _error = 'Os PINs não coincidem.');
        return;
      }
      try {
        await ParentalPinService.setPin(_pinController.text);
      } on FormatException catch (error) {
        setState(() => _error = error.message);
        return;
      }
      if (!mounted) return;
      ParentalSessionService.authenticate();
      _openDestination();
      return;
    }

    final locked = await ParentalPinService.remainingLockout();
    if (locked != null) {
      if (!mounted) return;
      setState(() {
        _isBlocked = true;
        _error = 'Acesso temporariamente bloqueado. Tente mais tarde.';
      });
      return;
    }
    final isValid = await ParentalPinService.checkPin(_pinController.text);
    if (!mounted) return;
    if (isValid) {
      ParentalSessionService.authenticate();
      _openDestination();
    } else {
      setState(() {
        _isBlocked = false;
        _error = 'PIN incorreto. Tente novamente.';
      });
      _pinController.clear();
    }
  }

  void _openDestination() {
    _authenticated = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            ParentalAreaTransitionScreen(destination: widget.destination),
      ),
    );
  }

  Widget _pinField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      obscureText: true,
      maxLength: 4,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: AppTheme.textDark,
        fontSize: 25,
        fontWeight: FontWeight.w700,
        letterSpacing: 9,
      ),
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        prefixIcon: const Icon(Icons.lock_outline, size: 20),
        filled: true,
        fillColor: const Color(0xFFF7F9FC),
        contentPadding: const EdgeInsets.symmetric(vertical: 17),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.primary, width: 2),
        ),
      ),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _submit(),
    );
  }

  Widget _pinIndicators(
    TextEditingController controller, {
    required String label,
  }) {
    return Semantics(
      label: '$label: ${controller.text.length} de 4 dígitos preenchidos',
      liveRegion: true,
      child: Row(
        key: ValueKey('pin-indicators-$label'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (index) {
          final filled = index < controller.text.length;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: filled ? 16 : 13,
            height: filled ? 16 : 13,
            margin: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              color: filled ? AppTheme.primary : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                color: filled ? AppTheme.primary : AppTheme.cardBorder,
                width: 2,
              ),
            ),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final title = _setupMode ? 'Criar acesso' : 'Acesso protegido';
    final description = _setupMode
        ? 'Crie um PIN pessoal de 4 dígitos para proteger as configurações.'
        : 'Digite o PIN do responsável para abrir a Área Parental.';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Área Parental'),
        backgroundColor: AppTheme.professionalBackground,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _GateBrandMark(),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: AppTheme.cardBorder),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1214213D),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _setupMode ? 'PRIMEIRO ACESSO' : 'ÁREA PROTEGIDA',
                          style: const TextStyle(
                            color: AppTheme.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          title,
                          style: const TextStyle(
                            color: AppTheme.textDark,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          description,
                          style: const TextStyle(
                            color: AppTheme.mutedText,
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 22),
                        if (_isBlocked) ...[
                          Container(
                            key: const ValueKey('pin-blocked-banner'),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF4E5),
                              borderRadius: BorderRadius.circular(12),
                              border:
                                  Border.all(color: const Color(0xFFF2C27B)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.lock_clock_outlined,
                                    color: Color(0xFF9A6700)),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Acesso bloqueado por segurança. Aguarde antes de tentar novamente.',
                                    style: TextStyle(
                                        color: Color(0xFF7A4F00), height: 1.3),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        _pinIndicators(
                          _pinController,
                          label: _setupMode ? 'Novo PIN' : 'PIN do responsável',
                        ),
                        const SizedBox(height: 10),
                        _pinField(
                          _setupMode ? 'Novo PIN' : 'PIN do responsável',
                          _pinController,
                        ),
                        if (_setupMode) ...[
                          const SizedBox(height: 12),
                          _pinIndicators(
                            _confirmController,
                            label: 'Confirmar PIN',
                          ),
                          const SizedBox(height: 10),
                          _pinField('Confirmar PIN', _confirmController),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF1F1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFF4C7C7),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  color: Color(0xFFB42318),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(
                                      color: Color(0xFFB42318),
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: _submit,
                          icon: Icon(
                            _setupMode
                                ? Icons.verified_user_outlined
                                : Icons.login_rounded,
                          ),
                          label: Text(
                            _setupMode ? 'Criar PIN e continuar' : 'Entrar',
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(54),
                            backgroundColor: AppTheme.professionalBackground,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Icon(
                              Icons.shield_outlined,
                              color: AppTheme.accentGreen,
                              size: 17,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Dados protegidos neste aparelho',
                              style: TextStyle(
                                color: AppTheme.mutedText,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_setupMode) ...[
                    const SizedBox(height: 14),
                    const Text(
                      'Evite combinações óbvias, como 1234 ou números repetidos. O PIN não é enviado para a internet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.mutedText,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GateBrandMark extends StatelessWidget {
  const _GateBrandMark();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: AppTheme.professionalBackground,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F14213D),
              blurRadius: 12,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: const Icon(
          Icons.shield_outlined,
          color: AppTheme.professionalAccent,
          size: 30,
        ),
      ),
    );
  }
}
