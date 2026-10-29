import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/user_model.dart';

/// This is a read-only route for the existing administrator member list.
/// Firestore continues to enforce access to the supplied profile stream.
Future<void> showMemberDetailsSheet(BuildContext context,
    {required AppUser viewer,
    required String memberId,
    required Stream<List<AppUser>> members}) async {
  if (!viewer.isAdmin || !viewer.isApproved) return;
  await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF1F6EF),
      builder: (_) => MemberDetailsSheet(memberId: memberId, members: members));
}

class MemberDetailsSheet extends StatelessWidget {
  const MemberDetailsSheet(
      {super.key, required this.memberId, required this.members});

  final String memberId;
  final Stream<List<AppUser>> members;

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .8,
        maxChildSize: .95,
        builder: (context, controller) => StreamBuilder<List<AppUser>>(
          stream: members,
          builder: (context, snapshot) {
            Widget content;
            if (snapshot.hasError) {
              content =
                  const Text('No se pudo cargar la información del miembro.');
            } else if (!snapshot.hasData) {
              content = const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()));
            } else {
              AppUser? current;
              for (final member in snapshot.data!) {
                if (member.userId == memberId && member.isApproved) {
                  current = member;
                  break;
                }
              }
              content = current == null
                  ? const Text('Este miembro ya no está disponible.')
                  : MemberProfileDetails(member: current);
            }
            return ListView(
                controller: controller,
                padding: EdgeInsets.fromLTRB(
                    20, 16, 20, 24 + MediaQuery.paddingOf(context).bottom),
                children: [content]);
          },
        ),
      );
}

/// Current profile fields only: no request history, editing or backend calls.
class MemberProfileDetails extends StatelessWidget {
  const MemberProfileDetails({super.key, required this.member});
  final AppUser member;

  static const _green = Color(0xFF276749);
  static const _text = Color(0xFF18201C);
  static const _secondary = Color(0xFF626C65);
  static const _border = Color(0xFFCDD7CE);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final role = member.isAdmin ? 'Administrador' : 'Vecino';
    final roleForeground = member.isAdmin ? const Color(0xFF35558A) : _green;
    final roleBackground = member.isAdmin
        ? const Color(0xFFE8EEF9)
        : const Color(0xFFD8EEDD);
    final roleStyle = (theme.textTheme.labelLarge ?? const TextStyle())
        .copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: roleForeground,
            height: 1.25);
    final scaler = MediaQuery.textScalerOf(context);
    final initials = member.nombre
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.characters.first.toUpperCase())
        .join();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Información del miembro',
          style: theme.textTheme.bodyMedium?.copyWith(color: _secondary)),
      const SizedBox(height: 14),
      LayoutBuilder(builder: (context, constraints) {
        final painter = TextPainter(
            text: TextSpan(text: role, style: roleStyle),
            textDirection: Directionality.of(context),
            textScaler: scaler)
          ..layout();
        final roleWidth =
            math.min(constraints.maxWidth, painter.width.ceilToDouble() + 50);
        painter.dispose();
        final inline =
            constraints.maxWidth - 70 - roleWidth >= scaler.scale(16) * 7.5;
        final badge = Container(
          key: const ValueKey('member-profile-role'),
          width: roleWidth,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: roleBackground,
              borderRadius: BorderRadius.circular(20)),
          child: Row(children: [
            Icon(
                member.isAdmin
                    ? Icons.admin_panel_settings_outlined
                    : Icons.person_outline_rounded,
                size: 18,
                color: roleForeground),
            const SizedBox(width: 6),
            Expanded(child: Text(role, style: roleStyle)),
          ]),
        );
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFFDCEBE0),
                foregroundColor: _green,
                child: Text(initials.isEmpty ? '?' : initials,
                    style: theme.textTheme.titleMedium?.copyWith(
                        color: _green, fontWeight: FontWeight.w700))),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(member.nombre,
                      key: const ValueKey('member-profile-name'),
                      style: theme.textTheme.titleLarge?.copyWith(
                          color: _text, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('Datos actuales del perfil',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: _secondary)),
                ])),
            if (inline) ...[const SizedBox(width: 10), badge],
          ]),
          if (!inline) ...[const SizedBox(height: 12), badge],
        ]);
      }),
      const SizedBox(height: 24),
      _section(context, 'Datos personales', [
        (Icons.badge_outlined, 'DNI', member.dni),
        (Icons.phone_outlined, 'Teléfono', member.phone ?? ''),
        (Icons.mail_outline_rounded, 'Correo electrónico', member.email),
      ]),
      const SizedBox(height: 20),
      _section(context, 'Datos de la comunidad', [
        (Icons.location_on_outlined, 'Dirección', member.address),
        (
          Icons.people_outline_rounded,
          'Tiempo en la comunidad',
          member.timeLivingHere
        ),
        (Icons.description_outlined, 'Motivo de ingreso', member.reason),
      ]),
    ]);
  }

  Widget _section(BuildContext context, String title,
      List<(IconData, String, String)> fields) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700, color: _text)),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: _border),
            borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          for (var index = 0; index < fields.length; index++) ...[
            if (index > 0) const Divider(height: 1, color: _border),
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child:
                              Icon(fields[index].$1, size: 23, color: _green)),
                      const SizedBox(width: 14),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(fields[index].$2,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: _secondary)),
                            const SizedBox(height: 4),
                            Text(
                                fields[index].$3.trim().isEmpty
                                    ? 'No indicado'
                                    : fields[index].$3,
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(color: _text, height: 1.4)),
                          ])),
                    ])),
          ],
        ]),
      ),
    ]);
  }
}
