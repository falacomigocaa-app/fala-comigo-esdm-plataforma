import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/invitation_service.dart';
import '../../data/access_grants.dart';
import '../widgets/parental_ui.dart';

class AccessManagementScreen extends StatefulWidget {
  const AccessManagementScreen({super.key});

  @override
  State<AccessManagementScreen> createState() => _AccessManagementScreenState();
}

class _AccessManagementScreenState extends State<AccessManagementScreen> {
  final _uuid = const Uuid();
  List<AccessGrant> _grants = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final grants = await AccessGrantStore.load();
    if (!mounted) return;
    setState(() {
      _grants = grants;
      _loading = false;
    });
  }

  Future<void> _addGrant() async {
    final result = await showModalBottomSheet<AccessGrant>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddAccessSheet(id: _uuid.v4()),
    );
    if (result == null) return;
    try {
      final invitation = await InvitationService.create(
        email: result.inviteeEmail ?? '',
        phone: result.inviteePhone,
        role: 'professional',
        scopes: _backendScopes(result.scopes),
      );
      final persistedGrant = result.copyWith(
        inviteLink: invitation['inviteLink']?.toString(),
      );
      await AccessGrantStore.save(persistedGrant);
      if (!mounted) return;
      setState(() => _grants = [..._grants, persistedGrant]);
    } on InvitationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_invitationError(error.code))),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Convite registrado e aguardando aceite.')),
    );
  }

  static List<String> _backendScopes(List<String> scopes) => scopes.map((scope) {
        switch (scope) {
          case 'Tarefas e retornos': return 'esdm_goal.read';
          case 'Perfil de comunicação': return 'access.read';
          case 'Rotina compartilhada': return 'routine.read';
          case 'Documentos publicados': return 'school_collection.read';
          default: return 'access.read';
        }
      }).toSet().toList();

  static String _invitationError(String code) => switch (code) {
        'AUTH_REQUIRED' || 'SESSION_EXPIRED' => 'Entre na conta online do responsável antes de convidar.',
        'INVITEE_REQUIRED' => 'Informe um e-mail ou WhatsApp para o convite.',
        _ => 'Não foi possível criar o convite. Verifique a conexão e tente novamente.',
      };

  Future<void> _revoke(AccessGrant grant) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Revogar acesso?'),
        content: Text(
          'A organização não poderá mais acessar o escopo autorizado para ${grant.personName}. A conta familiar e o modo offline continuam disponíveis.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Revogar acesso'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AccessGrantStore.revoke(grant);
    if (!mounted) return;
    setState(() {
      _grants = _grants
          .map(
            (item) => item.id == grant.id
                ? item.copyWith(status: AccessGrantStatus.revoked)
                : item,
          )
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Pessoas e organizações'),
        backgroundColor: AppTheme.professionalBackground,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addGrant,
        backgroundColor: AppTheme.professionalBackground,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Convidar'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
              children: [
                const ParentalSectionHeading(
                  eyebrow: 'CONTROLE DA FAMÍLIA',
                  title: 'Quem pode acessar?',
                  description:
                      'A licença e a autorização são coisas diferentes. Você decide o que cada organização pode ver.',
                ),
                const SizedBox(height: 18),
                const ParentalInfoBanner(
                  icon: Icons.verified_user_outlined,
                  eyebrow: 'PRIVACIDADE POR PADRÃO',
                  message:
                      'Clínicas, escolas e profissionais não recebem acesso automático aos cartões, documentos ou registros da criança.',
                ),
                const SizedBox(height: 18),
                if (_grants.isEmpty)
                  const ParentalSurface(
                    child: Column(
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 42,
                          color: AppTheme.primary,
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Nenhum acesso compartilhado',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'Convide uma clínica, escola ou profissional quando quiser compartilhar uma finalidade específica.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.mutedText,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ..._grants.map(
                    (grant) => _AccessGrantCard(
                      grant: grant,
                      onRevoke: grant.canRevoke ? () => _revoke(grant) : null,
                    ),
                  ),
                const SizedBox(height: 18),
                const ParentalSurface(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: AppTheme.primary),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Ao encerrar o vínculo, o acesso é revogado. Seus cartões, preferências e comunicação offline continuam no aparelho.',
                          style: TextStyle(
                            color: AppTheme.mutedText,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _AccessGrantCard extends StatelessWidget {
  final AccessGrant grant;
  final VoidCallback? onRevoke;

  const _AccessGrantCard({required this.grant, this.onRevoke});

  @override
  Widget build(BuildContext context) {
    final active = grant.status == AccessGrantStatus.active;
    final color = active ? AppTheme.accentGreen : AppTheme.mutedText;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                child: Icon(
                  _iconFor(grant.organizationKind),
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      grant.organizationName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${grant.organizationKindLabel} · ${grant.personName}',
                      style: const TextStyle(color: AppTheme.mutedText),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  grant.statusLabel,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            'Finalidade: ${grant.purpose}',
            style: const TextStyle(color: AppTheme.mutedText, height: 1.3),
          ),
          if (grant.inviteLink != null) ...[
            const SizedBox(height: 12),
            SelectableText(
              grant.inviteLink!,
              style: const TextStyle(color: AppTheme.primary, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => Share.share(
                    'Você foi convidado para o Fala Comigo. Acesse: ${grant.inviteLink}',
                  ),
                  icon: const Icon(Icons.share_outlined, size: 17),
                  label: const Text('Compartilhar'),
                ),
                TextButton.icon(
                  onPressed: grant.inviteePhone == null
                      ? null
                      : () => launchUrl(
                            Uri.parse(
                              "https://wa.me/${grant.inviteePhone!.replaceAll(RegExp(r'[^\d+]'), '')}?text=${Uri.encodeComponent('Você foi convidado para o Fala Comigo. Acesse: ${grant.inviteLink}')}",
                            ),
                            mode: LaunchMode.externalApplication,
                          ),
                  icon: const Icon(Icons.chat_outlined, size: 17),
                  label: const Text('WhatsApp'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: grant.scopes
                .map(
                  (scope) => Chip(
                    label: Text(scope),
                    visualDensity: VisualDensity.compact,
                    side: const BorderSide(color: AppTheme.cardBorder),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(
                Icons.event_outlined,
                size: 16,
                color: AppTheme.mutedText,
              ),
              const SizedBox(width: 5),
              Text(
                'Até ${_date(grant.expiresAt)}',
                style: const TextStyle(color: AppTheme.mutedText, fontSize: 12),
              ),
              const Spacer(),
              if (onRevoke != null)
                TextButton.icon(
                  onPressed: onRevoke,
                  icon: const Icon(Icons.block_outlined, size: 17),
                  label: const Text('Revogar'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(OrganizationKind kind) => switch (kind) {
        OrganizationKind.clinic => Icons.local_hospital_outlined,
        OrganizationKind.school => Icons.school_outlined,
        OrganizationKind.company => Icons.business_outlined,
        OrganizationKind.professional => Icons.badge_outlined,
      };

  static String _date(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _AddAccessSheet extends StatefulWidget {
  final String id;

  const _AddAccessSheet({required this.id});

  @override
  State<_AddAccessSheet> createState() => _AddAccessSheetState();
}

class _AddAccessSheetState extends State<_AddAccessSheet> {
  final _organizationController = TextEditingController();
  final _personController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  OrganizationKind _kind = OrganizationKind.clinic;
  final Set<String> _scopes = {'Tarefas e retornos'};

  static const _availableScopes = [
    'Tarefas e retornos',
    'Perfil de comunicação',
    'Rotina compartilhada',
    'Documentos publicados',
  ];

  @override
  void dispose() {
    _organizationController.dispose();
    _personController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_organizationController.text.trim().isEmpty ||
        (_emailController.text.trim().isEmpty && _phoneController.text.trim().isEmpty) ||
        _scopes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Preencha a organização, e-mail ou WhatsApp e ao menos um acesso.',
          ),
        ),
      );
      return;
    }
    final now = DateTime.now();
    Navigator.of(context).pop(
      AccessGrant(
        id: widget.id,
        organizationName: _organizationController.text.trim(),
        organizationKind: _kind,
        personName: _personController.text.trim(),
        role: 'Colaborador convidado',
        scopes: _scopes.toList(),
        status: AccessGrantStatus.pending,
        startsAt: now,
        expiresAt: now.add(const Duration(days: 90)),
        purpose: 'Coordenação autorizada com a família',
        inviteeEmail: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        inviteePhone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 22,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ParentalSectionHeading(
                eyebrow: 'NOVO VÍNCULO',
                title: 'Convidar organização',
                description:
                    'O convite será salvo no servidor e terá um link seguro para envio por e-mail ou WhatsApp.',
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _organizationController,
                decoration: parentalInputDecoration(
                  labelText: 'Nome da clínica, escola ou empresa',
                  icon: Icons.apartment_outlined,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<OrganizationKind>(
                initialValue: _kind,
                decoration: parentalInputDecoration(
                  labelText: 'Tipo de organização',
                  icon: Icons.category_outlined,
                ),
                items: OrganizationKind.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(_kindLabel(value)),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _kind = value ?? _kind),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _personController,
                decoration: parentalInputDecoration(
                  labelText: 'Pessoa de contato',
                  icon: Icons.person_outline,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: parentalInputDecoration(
                  labelText: 'E-mail do profissional, clínica ou escola',
                  icon: Icons.email_outlined,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: parentalInputDecoration(
                  labelText: 'WhatsApp (opcional)',
                  icon: Icons.chat_outlined,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Escopo inicial',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Comece pelo mínimo necessário. Você poderá revogar depois.',
                style: TextStyle(color: AppTheme.mutedText),
              ),
              const SizedBox(height: 6),
              ..._availableScopes.map(
                (scope) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _scopes.contains(scope),
                  title: Text(scope),
                  onChanged: (selected) => setState(() {
                    if (selected == true) {
                      _scopes.add(scope);
                    } else {
                      _scopes.remove(scope);
                    }
                  }),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.send_outlined),
                label: const Text('Registrar convite'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: AppTheme.professionalBackground,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _kindLabel(OrganizationKind value) => switch (value) {
        OrganizationKind.clinic => 'Clínica',
        OrganizationKind.school => 'Escola',
        OrganizationKind.company => 'Empresa patrocinadora',
        OrganizationKind.professional => 'Profissional independente',
      };
}
