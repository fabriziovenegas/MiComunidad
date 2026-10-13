import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../widgets/community_info_dialog.dart';

class NeighborDashboardScreen extends StatelessWidget {
  const NeighborDashboardScreen(
      {super.key, required this.user, required this.onNavigate});
  final AppUser user;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text('Hola, ${user.nombre.split(' ').first}',
            style: Theme.of(context).textTheme.headlineMedium),
        const Text('Participa y mantente al día con tu comunidad.'),
        const SizedBox(height: 18),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('events')
              .where('eventDate', isGreaterThanOrEqualTo: Timestamp.now())
              .orderBy('eventDate')
              .limit(1)
              .snapshots(),
          builder: (context, snapshot) {
            final event = snapshot.data?.docs.firstOrNull?.data();
            return Card(
              color: Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: .35),
              child: ListTile(
                leading: const Icon(Icons.event_available, size: 38),
                title: Text(
                    event?['title'] as String? ?? 'No hay reuniones próximas'),
                subtitle: Text(event?['location'] as String? ??
                    'La agenda se actualizará cuando se programe una actividad.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onNavigate(4),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        const CommunityInfoButton(),
        const SizedBox(height: 18),
        Text('Acciones rápidas', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: MediaQuery.sizeOf(context).width > 620 ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.15,
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
                onTap: () => onNavigate(3)),
            _Action(
                icon: Icons.calendar_month,
                label: 'Agenda',
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
                    'Comenta proyectos, aporta fotografías y registra necesidades de tu zona.'))),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
      child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon,
                        size: 34, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 8),
                    Text(label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold))
                  ]))));
}
