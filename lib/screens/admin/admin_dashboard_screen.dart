import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../widgets/community_info_dialog.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({
    super.key,
    required this.user,
    required this.onNavigate,
    this.firestore,
  });
  final AppUser user;
  final ValueChanged<int> onNavigate;
  final FirebaseFirestore? firestore;

  @override
  Widget build(BuildContext context) {
    final firstName = user.nombre.trim().split(RegExp(r'\s+')).first;
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(firstName.isEmpty ? 'Hola' : 'Hola, $firstName',
            style: Theme.of(context).textTheme.headlineMedium),
        const Text(
            'Gestiona la actividad de la comunidad desde un solo lugar.'),
        const SizedBox(height: 18),
        const CommunityInfoButton(),
        const SizedBox(height: 18),
        _AdaptiveCounts(
          children: [
            _Count(
                firestore: firestore,
                collection: 'accessRequests',
                label: 'Solicitudes',
                icon: Icons.person_add,
                onTap: () => onNavigate(3),
                whereField: 'status',
                whereValue: 'pendiente'),
            _Count(
                firestore: firestore,
                collection: 'projects',
                label: 'Proyectos',
                icon: Icons.construction,
                onTap: () => onNavigate(1)),
            _Count(
                firestore: firestore,
                collection: 'reports',
                label: 'Reportes',
                icon: Icons.report,
                whereNotField: 'moderationStatus',
                whereNotValue: 'rechazado',
                onTap: () => onNavigate(2)),
            _Count(
                firestore: firestore,
                collection: 'events',
                label: 'Actividades',
                icon: Icons.event,
                onTap: () => onNavigate(5)),
          ],
        ),
        const SizedBox(height: 20),
        Text('Accesos de administración',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Card(
          child: Column(
            children: [
              ListTile(
                  leading: const Icon(Icons.people),
                  title: const Text('Solicitudes y vecinos'),
                  subtitle: const Text('Aprobar, rechazar o retirar accesos'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onNavigate(3)),
              const Divider(height: 1),
              ListTile(
                  leading: const Icon(Icons.edit_calendar),
                  title: const Text('Agenda comunitaria'),
                  subtitle: const Text('Crear reuniones, subir fotos y actas'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onNavigate(5)),
              const Divider(height: 1),
              ListTile(
                  leading: const Icon(Icons.add_road),
                  title: const Text('Proyectos'),
                  subtitle: const Text('Crear y actualizar avances'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onNavigate(1)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(
      {required this.collection,
      required this.label,
      required this.icon,
      required this.onTap,
      this.whereField,
      this.firestore,
      this.whereNotField,
      this.whereValue,
      this.whereNotValue});
  final String collection;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final FirebaseFirestore? firestore;
  final String? whereField;
  final String? whereNotField;
  final Object? whereValue;
  final Object? whereNotValue;
  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> query =
        (firestore ?? FirebaseFirestore.instance).collection(collection);
    if (whereField != null) {
      query = query.where(whereField!, isEqualTo: whereValue);
    }
    if (whereNotField != null) {
      query = query.where(whereNotField!, isNotEqualTo: whereNotValue);
      if (whereField != null) {
        debugPrint(
            'Warning: Both whereField and whereNotField are provided for collection $collection. The whereNotField query will overwrite the whereField query.');
      }
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 8),
                  Text('${snapshot.data?.size ?? 0}',
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  Text(label)
                ]),
          ),
        ),
      ),
    );
  }
}

/// Equal height within each row, with room to grow for text and accessibility.
class _AdaptiveCounts extends StatelessWidget {
  const _AdaptiveCounts({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth > 684 ? 4 : 2;
          final tileWidth =
              (constraints.maxWidth - 12 * (columns - 1)) / columns;
          return Column(children: [
            for (var start = 0; start < children.length; start += columns) ...[
              if (start > 0) const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: tileWidth / 1.35),
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
