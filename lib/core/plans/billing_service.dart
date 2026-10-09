import 'dart:convert';

import 'package:http/http.dart' as http;

import '../services/auth_token_service.dart';
import 'plan_models.dart';

const billingApiBaseUrl = String.fromEnvironment(
  'PORTAL_API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8787',
);

class BillingCheckoutResult {
  const BillingCheckoutResult({required this.checkoutId, required this.status});

  final String checkoutId;
  final String status;
}

/// Integração do app com o contrato de billing sandbox.
/// Nenhum cartão, CVV ou dado financeiro é coletado neste cliente.
class BillingService {
  BillingService._();

  static final http.Client _client = http.Client();

  static Future<PlanLicense?> fetchSubscription() async {
    final token = await AuthTokenService.readToken();
    if (token == null || token.isEmpty) return null;
    final response = await _client.get(
      Uri.parse(billingApiBaseUrl).resolve('/v1/billing/subscription'),
      headers: {
        'accept': 'application/json',
        'authorization': 'Bearer $token',
      },
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['subscription'] is! Map) {
      return null;
    }
    return _licenseFromSubscription(
      Map<String, dynamic>.from(decoded['subscription'] as Map),
    );
  }

  static Future<BillingCheckoutResult> createSandboxCheckout(
    String planId,
  ) async {
    final token = await AuthTokenService.readToken();
    if (token == null || token.isEmpty) {
      throw StateError('É necessário entrar para iniciar uma assinatura.');
    }
    final response = await _client
        .post(
          Uri.parse(billingApiBaseUrl).resolve('/v1/billing/checkout'),
          headers: {
            'accept': 'application/json',
            'content-type': 'application/json',
            'authorization': 'Bearer $token',
          },
          body: jsonEncode({'planId': planId}),
        )
        .timeout(const Duration(seconds: 15));
    final decoded = jsonDecode(response.body);
    if (response.statusCode != 201 ||
        decoded is! Map<String, dynamic> ||
        decoded['checkout'] is! Map) {
      final error = decoded is Map<String, dynamic> ? decoded['error'] : null;
      throw StateError(error is String ? error : 'CHECKOUT_INDISPONIVEL');
    }
    final checkout = Map<String, dynamic>.from(decoded['checkout'] as Map);
    return BillingCheckoutResult(
      checkoutId: checkout['id'] as String,
      status: checkout['status'] as String,
    );
  }

  static PlanLicense _licenseFromSubscription(
    Map<String, dynamic> subscription,
  ) {
    final status = switch (subscription['status'] as String? ?? '') {
      'active' => LicenseStatus.active,
      'grace' => LicenseStatus.grace,
      'suspended' => LicenseStatus.suspended,
      'canceled' || 'expired' => LicenseStatus.expired,
      _ => LicenseStatus.invited,
    };
    final createdAt = DateTime.tryParse(
          subscription['createdAt'] as String? ?? '',
        ) ??
        DateTime.now();
    final expiresAt = DateTime.tryParse(
      subscription['currentPeriodEnd'] as String? ?? '',
    );
    return PlanLicense(
      id: subscription['id'] as String,
      planId: subscription['planId'] as String,
      status: status,
      issuedAt: createdAt,
      expiresAt: expiresAt,
    );
  }
}
