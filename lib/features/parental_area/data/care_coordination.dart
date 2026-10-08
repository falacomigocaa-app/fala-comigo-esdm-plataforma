import '../../../../core/services/secure_box_service.dart';
import '../../../../core/services/parental_session_service.dart';

enum CarePlanStatus { draft, active, needsReview, archived }

enum AppointmentStatus { scheduled, confirmed, cancelled, completed }

class CommunicationProfile {
  final String subjectId;
  final String communicationModes;
  final String preferredAccess;
  final String facilitators;
  final String avoid;
  final String contingencyPlan;
  final String partners;
  final DateTime? reviewAt;
  final DateTime updatedAt;

  const CommunicationProfile({
    required this.subjectId,
    required this.communicationModes,
    required this.preferredAccess,
    required this.facilitators,
    required this.avoid,
    required this.contingencyPlan,
    required this.partners,
    required this.reviewAt,
    required this.updatedAt,
  });

  factory CommunicationProfile.empty() => CommunicationProfile(
        subjectId: 'local-subject',
        communicationModes: '',
        preferredAccess: '',
        facilitators: '',
        avoid: '',
        contingencyPlan: '',
        partners: '',
        reviewAt: null,
        updatedAt: DateTime.now(),
      );

  CommunicationProfile copyWith({
    String? communicationModes,
    String? preferredAccess,
    String? facilitators,
    String? avoid,
    String? contingencyPlan,
    String? partners,
    DateTime? reviewAt,
  }) =>
      CommunicationProfile(
        subjectId: subjectId,
        communicationModes: communicationModes ?? this.communicationModes,
        preferredAccess: preferredAccess ?? this.preferredAccess,
        facilitators: facilitators ?? this.facilitators,
        avoid: avoid ?? this.avoid,
        contingencyPlan: contingencyPlan ?? this.contingencyPlan,
        partners: partners ?? this.partners,
        reviewAt: reviewAt ?? this.reviewAt,
        updatedAt: DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'subjectId': subjectId,
        'communicationModes': communicationModes,
        'preferredAccess': preferredAccess,
        'facilitators': facilitators,
        'avoid': avoid,
        'contingencyPlan': contingencyPlan,
        'partners': partners,
        'reviewAt': reviewAt?.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory CommunicationProfile.fromMap(Map<dynamic, dynamic> map) =>
      CommunicationProfile(
        subjectId: '${map['subjectId'] ?? 'local-subject'}',
        communicationModes: '${map['communicationModes'] ?? ''}',
        preferredAccess: '${map['preferredAccess'] ?? ''}',
        facilitators: '${map['facilitators'] ?? ''}',
        avoid: '${map['avoid'] ?? ''}',
        contingencyPlan: '${map['contingencyPlan'] ?? ''}',
        partners: '${map['partners'] ?? ''}',
        reviewAt: DateTime.tryParse('${map['reviewAt'] ?? ''}'),
        updatedAt:
            DateTime.tryParse('${map['updatedAt'] ?? ''}') ?? DateTime.now(),
      );
}

class CommunicationPlan {
  final String id;
  final String title;
  final String context;
  final String functionalGoal;
  final String strategy;
  final String familyAction;
  final String schoolAction;
  final DateTime? reviewAt;
  final CarePlanStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CommunicationPlan({
    required this.id,
    required this.title,
    required this.context,
    required this.functionalGoal,
    required this.strategy,
    required this.familyAction,
    required this.schoolAction,
    required this.reviewAt,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  String get statusLabel => switch (status) {
        CarePlanStatus.draft => 'Rascunho',
        CarePlanStatus.active => 'Ativo',
        CarePlanStatus.needsReview => 'Precisa de revisão',
        CarePlanStatus.archived => 'Arquivado',
      };

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'context': context,
        'functionalGoal': functionalGoal,
        'strategy': strategy,
        'familyAction': familyAction,
        'schoolAction': schoolAction,
        'reviewAt': reviewAt?.toIso8601String(),
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory CommunicationPlan.fromMap(
    Map<dynamic, dynamic> map,
  ) =>
      CommunicationPlan(
        id: '${map['id']}',
        title: '${map['title'] ?? ''}',
        context: '${map['context'] ?? ''}',
        functionalGoal: '${map['functionalGoal'] ?? ''}',
        strategy: '${map['strategy'] ?? ''}',
        familyAction: '${map['familyAction'] ?? ''}',
        schoolAction: '${map['schoolAction'] ?? ''}',
        reviewAt: DateTime.tryParse('${map['reviewAt'] ?? ''}'),
        status: CarePlanStatus.values.firstWhere(
          (value) => value.name == map['status'],
          orElse: () => CarePlanStatus.draft,
        ),
        createdAt:
            DateTime.tryParse('${map['createdAt'] ?? ''}') ?? DateTime.now(),
        updatedAt:
            DateTime.tryParse('${map['updatedAt'] ?? ''}') ?? DateTime.now(),
      );
}

class Appointment {
  final String id;
  final String title;
  final String organization;
  final String professional;
  final DateTime startsAt;
  final int durationMinutes;
  final String preparation;
  final AppointmentStatus status;
  final bool reminderEnabled;

  const Appointment({
    required this.id,
    required this.title,
    required this.organization,
    required this.professional,
    required this.startsAt,
    required this.durationMinutes,
    required this.preparation,
    required this.status,
    required this.reminderEnabled,
  });

  String get statusLabel => switch (status) {
        AppointmentStatus.scheduled => 'Agendado',
        AppointmentStatus.confirmed => 'Confirmado',
        AppointmentStatus.cancelled => 'Cancelado',
        AppointmentStatus.completed => 'Concluído',
      };

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'organization': organization,
        'professional': professional,
        'startsAt': startsAt.toIso8601String(),
        'durationMinutes': durationMinutes,
        'preparation': preparation,
        'status': status.name,
        'reminderEnabled': reminderEnabled,
      };

  factory Appointment.fromMap(Map<dynamic, dynamic> map) => Appointment(
        id: '${map['id']}',
        title: '${map['title'] ?? ''}',
        organization: '${map['organization'] ?? ''}',
        professional: '${map['professional'] ?? ''}',
        startsAt:
            DateTime.tryParse('${map['startsAt'] ?? ''}') ?? DateTime.now(),
        durationMinutes: (map['durationMinutes'] as num?)?.toInt() ?? 45,
        preparation: '${map['preparation'] ?? ''}',
        status: AppointmentStatus.values.firstWhere(
          (value) => value.name == map['status'],
          orElse: () => AppointmentStatus.scheduled,
        ),
        reminderEnabled: map['reminderEnabled'] != false,
      );
}

class CareCoordinationStore {
  CareCoordinationStore._();

  static const profileBox = 'communication_profile';
  static const plansBox = 'communication_plans';
  static const appointmentsBox = 'care_appointments';

  static Future<CommunicationProfile> loadProfile() async {
    ParentalSessionService.requireAuthenticated();
    final box = await SecureBoxService.openSecureBox(profileBox);
    final raw = box.get('data') as Map?;
    return raw == null
        ? CommunicationProfile.empty()
        : CommunicationProfile.fromMap(raw);
  }

  static Future<void> saveProfile(CommunicationProfile profile) async {
    ParentalSessionService.requireAuthenticated();
    final box = await SecureBoxService.openSecureBox(profileBox);
    await box.put('data', profile.toMap());
  }

  static Future<List<CommunicationPlan>> loadPlans() async {
    ParentalSessionService.requireAuthenticated();
    final box = await SecureBoxService.openSecureBox(plansBox);
    return box.values.whereType<Map>().map(CommunicationPlan.fromMap).toList();
  }

  static Future<void> savePlan(CommunicationPlan plan) async {
    ParentalSessionService.requireAuthenticated();
    final box = await SecureBoxService.openSecureBox(plansBox);
    await box.put(plan.id, plan.toMap());
  }

  static Future<List<Appointment>> loadAppointments() async {
    ParentalSessionService.requireAuthenticated();
    final box = await SecureBoxService.openSecureBox(appointmentsBox);
    return box.values.whereType<Map>().map(Appointment.fromMap).toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }

  static Future<void> saveAppointment(Appointment appointment) async {
    ParentalSessionService.requireAuthenticated();
    final box = await SecureBoxService.openSecureBox(appointmentsBox);
    await box.put(appointment.id, appointment.toMap());
  }
}
