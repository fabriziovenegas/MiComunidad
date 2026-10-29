import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/access_request.dart';
import '../utils/request_rejection_reason.dart';

/// Read-only presentation. Request updates, permissions and actions stay in the
/// administrator screen; this widget never reads or writes Firebase.
class AccessRequestDetails extends StatelessWidget {
  const AccessRequestDetails({super.key, required this.request});

  final AccessRequest request;
  static const _green = Color(0xFF276749);
  static const _text = Color(0xFF18201C);
  static const _secondary = Color(0xFF626C65);
  static const _border = Color(0xFFCDD7CE);
  static const _rejectionBackground = Color(0xFFFFF0F0);
  static const _rejectionText = Color(0xFFA52B2B);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initials = request.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.characters.first.toUpperCase())
        .join();
    final (label, icon, background, foreground) = switch (request.status) {
      'pendiente' => (
          'Pendiente',
          Icons.hourglass_top_rounded,
          const Color(0xFFFFF3CD),
          const Color(0xFF795600)
        ),
      'aprobado' => (
          'Aprobada',
          Icons.check_circle_outline_rounded,
          const Color(0xFFD8EEDD),
          const Color(0xFF236344)
        ),
      'rechazado' => (
          'Rechazada',
          Icons.cancel_outlined,
          const Color(0xFFFCE4E4),
          _rejectionText
        ),
      'retirado' => (
          'Acceso retirado',
          Icons.person_off_outlined,
          const Color(0xFFECEFF1),
          const Color(0xFF455A64)
        ),
      _ => (
          request.status,
          Icons.info_outline_rounded,
          const Color(0xFFECEFF1),
          const Color(0xFF455A64)
        ),
    };
    final badge = Container(
      key: const ValueKey('access-request-status'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: background, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: foreground),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label,
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: foreground, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Solicitud de acceso',
          style: theme.textTheme.bodyMedium?.copyWith(color: _secondary)),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, constraints) {
        final inlineStatus = constraints.maxWidth >= 350 &&
            MediaQuery.textScalerOf(context).scale(14) <= 17;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: const Color(0xFFDCEBE0),
              foregroundColor: _green,
              child: Text(initials.isEmpty ? '?' : initials,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: _green, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(request.name,
                        style: theme.textTheme.titleLarge?.copyWith(
                            color: _text, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                        'Enviada el ${DateFormat('dd/MM/yyyy').format(request.createdAt)}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: _secondary)),
                  ]),
            ),
            if (inlineStatus) ...[
              const SizedBox(width: 10),
              ConstrainedBox(
                  constraints:
                      BoxConstraints(maxWidth: constraints.maxWidth * .45),
                  child: badge),
            ],
          ]),
          if (!inlineStatus) ...[
            const SizedBox(height: 12),
            badge,
          ],
        ]);
      }),
      if (request.status == 'rechazado') ...[
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: _rejectionBackground,
              border: Border.all(color: const Color(0xFFF0BDBD)),
              borderRadius: BorderRadius.circular(14)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline_rounded,
                color: _rejectionText, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Motivo del rechazo',
                        style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: _rejectionText)),
                    const SizedBox(height: 6),
                    Text(requestRejectionReason(request.rejectionReason),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: _text, height: 1.4)),
                  ]),
            ),
          ]),
        ),
      ],
      const SizedBox(height: 20),
      _section(context, 'Datos personales', [
        (Icons.badge_outlined, 'DNI', request.dni),
        (Icons.phone_outlined, 'Teléfono', request.phone),
        (Icons.mail_outline_rounded, 'Correo electrónico', request.email),
      ]),
      const SizedBox(height: 20),
      _section(context, 'Datos de la comunidad', [
        (Icons.location_on_outlined, 'Dirección', request.address),
        (
          Icons.people_outline_rounded,
          'Tiempo en la comunidad',
          request.timeLivingHere
        ),
        (Icons.description_outlined, 'Motivo de ingreso', request.reason),
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
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Icon(fields[index].$1, size: 23, color: _green),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fields[index].$2,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: _secondary)),
                        const SizedBox(height: 4),
                        Text(fields[index].$3,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: _text, height: 1.4)),
                      ]),
                ),
              ]),
            ),
          ],
        ]),
      ),
    ]);
  }
}
