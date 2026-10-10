import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../../core/services/auth_token_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/login_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final success = await ref.read(loginControllerProvider.notifier).login(
          email: _emailController.text,
          password: _passwordController.text,
        );
    if (success && mounted) {
      try {
        final organization = await AuthTokenService.readOrganizationId();
        final token = await AuthTokenService.readToken();
        final response = await http.get(
            Uri.parse(authApiBaseUrl).resolve(
                '/v1/organizations/${Uri.encodeComponent(organization ?? '')}/subjects'),
            headers: {
              'authorization': 'Bearer $token'
            }).timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) {
          throw StateError(
              'Não foi possível consultar os pacientes autorizados.');
        }
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final subjects =
            (data['subjects'] as List).cast<Map<String, dynamic>>();
        if (!mounted) return;
        if (subjects.isEmpty) {
          throw StateError(
              'Sua conta ainda não tem pacientes autorizados. Solicite o vínculo ao responsável.');
        }
        final selected = subjects.length == 1
            ? subjects.single['id'] as String
            : await showDialog<String>(
                context: context,
                builder: (context) => SimpleDialog(
                    title: const Text('Selecione o paciente'),
                    children: subjects
                        .map((subject) => SimpleDialogOption(
                            onPressed: () =>
                                Navigator.pop(context, subject['id'] as String),
                            child: Text(subject['displayName'] as String)))
                        .toList()));
        if (selected == null) return;
        await AuthTokenService.selectSubject(selected);
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/coleta-escola');
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(error is StateError
                  ? error.message.toString()
                  : 'Não foi possível carregar os pacientes. Verifique sua conexão.')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(loginControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Entrar no Portal')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.verified_user_outlined, size: 64),
                    const SizedBox(height: 20),
                    Text(
                      'Acesso profissional',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Use suas credenciais do Portal Cuidado Conectado.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (value) =>
                          value == null || !value.contains('@')
                              ? 'Informe um email válido.'
                              : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(labelText: 'Senha'),
                      validator: (value) => value == null || value.length < 8
                          ? 'Informe sua senha.'
                          : null,
                    ),
                    if (state.errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        state.errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: state.loading ? null : _submit,
                      icon: state.loading
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login),
                      label: Text(state.loading ? 'Entrando…' : 'Entrar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
