import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/services/secure_box_service.dart';
import '../../../core/services/parental_session_service.dart';

const _boxName = 'parent_access_grants';

enum OrganizationKind { clinic, school, company, professional }

enum AccessGrantStatus { pending, active, revoked, expired }

@immutable
class AccessGrant {
  final String id;
  final String organizationName;
  final OrganizationKind organizationKind;
  final String personName;
  final String role;
  final List<String> scopes;
  final AccessGrantStatus status;
  final DateTime startsAt;
  final DateTime expiresAt;
  final String purpose;

  const AccessGrant({
    required this.id,
    required this.organizationName,
    required this.organizationKind,
    required this.personName,
    required this.role,
    required this.scopes,
    required this.status,
    required this.startsAt,
    required this.expiresAt,
    required this.purpose,
  });

  AccessGrant copyWith({AccessGrantStatus? status, DateTime? expiresAt}) =>
      AccessGrant(
        id: id,
        organizationName: organizationName,
        organizationKind: organizationKind,
        personName: personName,
        role: role,
        scopes: scopes,
        status: status ?? this.status,
        startsAt: startsAt,
        expiresAt: expiresAt ?? this.expiresAt,
        purpose: purpose,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'organizationName': organizationName,
        'organizationKind': organizationKind.name,
        'personName': personName,
        'role': role,
        'scopes': scopes,
        'status': status.name,
        'startsAt': startsAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'purpose': purpose,
      };

  factory AccessGrant.fromMap(Map<dynamic, dynamic> map) => AccessGrant(
        id: '${map['id'] ?? ''}',
        organizationName: '${map['organizationName'] ?? ''}',
        organizationKind: OrganizationKind.values.firstWhere(
          (value) => value.name == map['organizationKind'],
          orElse: () => OrganizationKind.professional,
        ),
        personName: '${map['personName'] ?? ''}',
        role: '${map['role'] ?? 'Colaborador'}',
        scopes: (map['scopes'] as List?)?.map((value) => '$value').toList() ??
            const [],
        status: AccessGrantStatus.values.firstWhere(
          (value) => value.name == map['status'],
          orElse: () => AccessGrantStatus.pending,
        ),
        startsAt: DateTime.tryParse('${map['startsAt']}') ?? DateTime.now(),
        expiresAt: DateTime.tryParse('${map['expiresAt']}') ??
            DateTime.now().add(const Duration(days: 90)),
        purpose: '${map['purpose'] ?? ''}',
      );

  String get organizationKindLabel => switch (organizationKind) {
        OrganizationKind.clinic => 'Clínica',
        OrganizationKind.school => 'Escola',
        OrganizationKind.company => 'Patrocinador',
        OrganizationKind.professional => 'Profissional',
      };

  String get statusLabel => switch (status) {
        AccessGrantStatus.pending => 'Aguardando aceite',
        AccessGrantStatus.active => 'Ativo',
        AccessGrantStatus.revoked => 'Revogado',
        AccessGrantStatus.expired => 'Expirado',
      };

  bool get canRevoke =>
      status == AccessGrantStatus.pending || status == AccessGrantStatus.active;
}

class AccessGrantStore {
  AccessGrantStore._();

  static Future<Box> _box() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    return SecureBoxService.openSecureBox(_boxName);
  }

  static Future<List<AccessGrant>> load() async {
    ParentalSessionService.requireAuthenticated();
    final box = await _box();
    return box.values
        .whereType<Map>()
        .map(AccessGrant.fromMap)
        .where((grant) => grant.id.isNotEmpty)
        .toList()
      ..sort((a, b) => a.expiresAt.compareTo(b.expiresAt));
  }

  static Future<void> save(AccessGrant grant) async {
    ParentalSessionService.requireAuthenticated();
    final box = await _box();
    await box.put(grant.id, grant.toMap());
  }

  static Future<void> revoke(AccessGrant grant) async {
    await save(grant.copyWith(status: AccessGrantStatus.revoked));
  }
}
