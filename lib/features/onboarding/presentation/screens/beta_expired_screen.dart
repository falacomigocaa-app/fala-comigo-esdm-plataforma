import 'package:flutter/material.dart';

class BetaExpiredScreen extends StatelessWidget {
  const BetaExpiredScreen({super.key, required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    final message = reason == 'clock_rollback'
        ? 'O relógio deste dispositivo parece ter sido alterado. Conecte-se à internet e ajuste a data e a hora para continuar.'
        : reason == 'not_started'
            ? 'O ciclo de avaliação ainda não começou.'
            : 'O período de avaliação selecionada terminou. Entre em contato com a equipe do beta para obter uma nova autorização.';
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_clock_outlined,
                  size: 64, color: Color(0xFF1D5C82)),
              const SizedBox(height: 20),
              const Text(
                'Avaliação beta indisponível',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
