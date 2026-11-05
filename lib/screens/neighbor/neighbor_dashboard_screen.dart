import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../widgets/community_info_dialog.dart';
import '../../widgets/admin_upcoming_event_card.dart';

class NeighborDashboardScreen extends StatelessWidget {
  const NeighborDashboardScreen(
      {super.key,
      required this.user,
      required this.onNavigate,
      this.firestore,
      this.now});
  final AppUser user;
  final ValueChanged<int> onNavigate;
  final FirebaseFirestore? firestore;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text('Hola, ${user.nombre.split(' ').first}',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const Text('Participa y mantente al día con tu comunidad.'),
        const SizedBox(height: 18),
        AdminUpcomingEventCard(
            firestore: firestore ?? FirebaseFirestore.instance,
            now: now,
            onOpenAgenda: () => onNavigate(4)),
        const SizedBox(height: 12),
        const CommunityInfoButton(compact: true),
        const SizedBox(height: 22),
        Text('Acciones rápidas',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        _AdaptiveActions(
          children: [
            _Action(
                icon: Icons.map, label: 'Ver mapa', onTap: () => onNavigate(1)),
            _Action(
                icon: Icons.construction,
                label: 'Proyectos',
                onTap: () => onNavigate(2)),
            _Action(
                icon: Icons.add_alert,
                label: 'Nuevo reporte',
                iconBackground: const Color(0xFFFFEDD1),
                onTap: () => onNavigate(3)),
            _Action(
                icon: Icons.calendar_month,
                label: 'Agenda',
                iconBackground: const Color(0xFFE1EEFA),
                onTap: () => onNavigate(4)),
          ],
        ),
        const SizedBox(height: 18),
        Text('Actividad comunitaria',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        const Card(
            child: ListTile(
                leading: Icon(Icons.groups),
                title: Text('Tu participación cuenta'),
                subtitle: Text(
                    'Comenta proyectos, comparte fotos y reporta necesidades de la comunidad.'))),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.iconBackground = const Color(0xFFE4F3E9)});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color iconBackground;
  @override
  Widget build(BuildContext context) => Card(
      margin: EdgeInsets.zero,
      child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                            color: iconBackground,
                            borderRadius: BorderRadius.circular(12)),
                        child: Icon(icon,
                            size: 24, color: const Color(0xFF276749))),
                    const SizedBox(height: 8),
                    Text(label,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF526258)))
                  ]))));
}

/// Keep each row balanced while allowing larger text to increase its height.
class _AdaptiveActions extends StatelessWidget {
  const _AdaptiveActions({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth > 584 ? 4 : 2;
          return Column(children: [
            for (var start = 0; start < children.length; start += columns) ...[
              if (start > 0) const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 108),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = start;
                          i < start + columns && i < children.length;
                          i++) ...[
                        if (i > start) const SizedBox(width: 12),
                        Expanded(child: children[i]),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ]);
        },
      );
}
