import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/access_request.dart';
import '../../models/user_model.dart';
import '../../services/community_service.dart';

class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key, required this.user});
  final AppUser user;
  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  String? _busyId;
  final Map<String, AccessRequest> _currentRequests = {};

  bool _canApprove(AccessRequest request) =>
      widget.user.isAdmin &&
      (request.status == 'pendiente' || request.status == 'rechazado');

  bool _canReject(AccessRequest request) =>
      widget.user.isAdmin && request.status == 'pendiente';
  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _review(AccessRequest request, bool approve) async {
    request = _currentRequests[request.id] ?? request;
    if (_busyId != null ||
        !(approve ? _canApprove(request) : _canReject(request))) {
      return;
    }
    String? reason;
    if (!approve) {
      var inputReason = '';
      reason = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('Rechazar solicitud'),
                  content: TextField(
                      onChanged: (value) => inputReason = value,
                      maxLines: 3,
                      decoration: const InputDecoration(
                          labelText: 'Motivo del rechazo')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, inputReason),
                        child: const Text('Rechazar'))
                  ]));
      if (reason == null) return;
    }
    if (!mounted) return;
    request = _currentRequests[request.id] ?? request;
    if (_busyId != null ||
        !(approve ? _canApprove(request) : _canReject(request))) {
      return;
    }
    setState(() => _busyId = request.id);
    try {
      await CommunityService.instance.reviewAccessRequest(
          requestId: request.id, approve: approve, reason: reason);
      if (approve) {
        try {
          await FirebaseAuth.instance
              .sendPasswordResetEmail(email: request.email);
        } on FirebaseAuthException {
          // La aprobación ya se guardó. El administrador puede reenviar el
          // enlace desde la pantalla de inicio de sesión si el correo falló.
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(approve
                ? 'Vecino aprobado y cuenta creada.'
                : 'Solicitud rechazada.')));
      }
    } catch (error) {
      if (mounted) {
        String message = "No se pudo completar la acción";

        if (error is FirebaseFunctionsException) {
          if (error.code == 'failed-precondition') {
            message = request.status == 'rechazado' && approve
                ? 'El servicio todavía no permite aprobar una solicitud rechazada.'
                : 'Esta solicitud ya fue revisada. Actualiza la lista.';
          }
        }
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _deleteRequest(AccessRequest request) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar solicitud'),
        content: Text(
          '¿Deseas eliminar la solicitud de ${request.name}? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _busyId = request.id);

    try {
      debugPrint('🟡 INICIO: eliminando solicitud ${request.id}');

      await CommunityService.instance.deleteAccessRequest(request.id);

      debugPrint('🟢 FIN: solicitud eliminada correctamente');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Solicitud eliminada.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo eliminar la solicitud: $error'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
      }
    }
  }

  Future<void> _remove(AppUser user) async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Retirar acceso'),
                content: Text('¿Deseas retirar el acceso de ${user.nombre}? '
                    'Sus solicitudes aprobadas se conservarán como historial de acceso retirado.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Retirar'))
                ]));
    if (confirm != true) return;
    setState(() => _busyId = user.userId);
    try {
      await CommunityService.instance.removeNeighbor(user.userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Miembro retirado y solicitudes actualizadas.'),
        ));
      }
    } catch (error) {
      if (mounted) {
        final message = error is FirebaseFunctionsException
            ? error.message ??
                'No se pudo completar la baja. Inténtalo nuevamente.'
            : 'No se pudo completar la baja. Inténtalo nuevamente.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _setRole(AppUser user, UserRole role) async {
    final nextLabel = role == UserRole.admin ? 'administrador' : 'vecino';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cambiar rol'),
        content: Text(
          '¿Deseas convertir a ${user.nombre} en $nextLabel?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _busyId = user.userId);
    try {
      await CommunityService.instance.setUserRole(user.userId, role);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user.nombre} ahora es $nextLabel.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo cambiar el rol: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  void _details(AccessRequest selectedRequest) {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => StreamBuilder<List<AccessRequest>>(
              stream: CommunityService.instance.accessRequests(),
              initialData: [selectedRequest],
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                        'No se pudo actualizar el estado de la solicitud.'),
                  );
                }
                AccessRequest? currentRequest;
                for (final item in snapshot.data ?? <AccessRequest>[]) {
                  if (item.id == selectedRequest.id) currentRequest = item;
                }
                if (currentRequest == null) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Esta solicitud ya no está disponible.'),
                  );
                }
                final request = currentRequest;
                return DraggableScrollableSheet(
                    expand: false,
                    initialChildSize: .8,
                    maxChildSize: .95,
                    builder: (_, controller) => ListView(
                            controller: controller,
                            padding: const EdgeInsets.all(20),
                            children: [
                              Text(request.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall),
                              const SizedBox(height: 12),
                              _detail(
                                  'Estado',
                                  request.status == 'pendiente'
                                      ? 'Pendiente'
                                      : request.status == 'rechazado'
                                          ? 'Rechazada'
                                          : request.status == 'retirado'
                                              ? 'Acceso retirado'
                                              : request.status == 'aprobado'
                                                  ? 'Aprobada'
                                                  : request.status),
                              _detail('DNI', request.dni),
                              _detail('Teléfono', request.phone),
                              _detail('Correo', request.email),
                              _detail('Dirección', request.address),
                              _detail('Tiempo viviendo aquí',
                                  request.timeLivingHere),
                              _detail('Motivo', request.reason),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                  onPressed: () => launchUrl(
                                      Uri.parse(request.identityDocumentUrl),
                                      mode: LaunchMode.externalApplication),
                                  icon: const Icon(Icons.description),
                                  label: const Text('Abrir documento adjunto')),
                              if (_canApprove(request) ||
                                  _canReject(request)) ...[
                                const SizedBox(height: 10),
                                Row(children: [
                                  if (_canReject(request))
                                    Expanded(
                                        child: OutlinedButton.icon(
                                            onPressed: _busyId == null
                                                ? () async {
                                                    Navigator.pop(context);
                                                    await Future<void>.delayed(
                                                        const Duration(
                                                            milliseconds: 100));
                                                    if (mounted) {
                                                      _review(request, false);
                                                    }
                                                  }
                                                : null,
                                            icon: const Icon(Icons.close),
                                            label: const Text('Rechazar'))),
                                  if (_canReject(request) &&
                                      _canApprove(request))
                                    const SizedBox(width: 10),
                                  if (_canApprove(request))
                                    Expanded(
                                        child: FilledButton.icon(
                                            onPressed: _busyId == null
                                                ? () {
                                                    Navigator.pop(context);
                                                    _review(request, true);
                                                  }
                                                : null,
                                            icon: const Icon(Icons.check),
                                            label: const Text('Aprobar')))
                                ]),
                              ],
                            ]));
              },
            ));
  }

  Widget _detail(String label, String value) => ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(value));

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
            controller: _tabs,
            tabs: const [Tab(text: 'Solicitudes'), Tab(text: 'Miembros')]),
        Expanded(
          child: TabBarView(controller: _tabs, children: [
            StreamBuilder<List<AccessRequest>>(
              stream: CommunityService.instance.accessRequests(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                      child: Text('No se pudieron cargar las solicitudes.'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final requests = snapshot.data!;
                _currentRequests
                  ..clear()
                  ..addEntries(
                      requests.map((request) => MapEntry(request.id, request)));
                if (requests.isEmpty) {
                  return const _Empty(
                      icon: Icons.person_search, text: 'No hay solicitudes.');
                }
                return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: requests.length,
                    itemBuilder: (context, index) {
                      final request = requests[index];
                      final pending = request.status == 'pendiente';
                      final rejected = request.status == 'rechazado';
                      final prettyStatus = pending
                          ? 'Pendiente'
                          : rejected
                              ? 'Rechazada'
                              : request.status == 'retirado'
                                  ? 'Acceso retirado'
                                  : request.status == 'aprobado'
                                      ? 'Aprobada'
                                      : request.status;
                      return Card(
                        child: InkWell(
                          onTap: () => _details(request),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  child: Text(
                                    request.name.isEmpty
                                        ? '?'
                                        : request.name[0],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        request.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${DateFormat('dd/MM/yyyy').format(request.createdAt)} · $prettyStatus',
                                      ),
                                    ],
                                  ),
                                ),
                                if (pending)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Rechazar',
                                        onPressed: _busyId == null
                                            ? () => _review(request, false)
                                            : null,
                                        icon: const Icon(Icons.close),
                                      ),
                                      IconButton(
                                        tooltip: 'Aprobar',
                                        onPressed: _busyId == null
                                            ? () => _review(request, true)
                                            : null,
                                        icon: const Icon(Icons.check_circle),
                                      ),
                                    ],
                                  )
                                else if (rejected)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Aprobar',
                                        onPressed: _busyId == null &&
                                                _canApprove(request)
                                            ? () => _review(request, true)
                                            : null,
                                        icon: const Icon(Icons.check_circle),
                                      ),
                                      IconButton(
                                        tooltip: 'Eliminar solicitud',
                                        onPressed: _busyId == null
                                            ? () => _deleteRequest(request)
                                            : null,
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  )
                                else
                                  const Icon(Icons.chevron_right),
                              ],
                            ),
                          ),
                        ),
                      );
                    });
              },
            ),
            StreamBuilder<List<AppUser>>(
              stream: CommunityService.instance.members(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final users = snapshot.data!;
                if (users.isEmpty) {
                  return const _Empty(
                      icon: Icons.people_outline,
                      text: 'Todavía no hay miembros aprobados.');
                }
                return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final user = users[index];
                      return Card(
                          child: ListTile(
                              leading: CircleAvatar(child: Text(user.initials)),
                              title: Text(user.nombre),
                              subtitle: Text(
                                  '${user.email}\n${user.isAdmin ? 'Administrador' : 'Vecino'}'),
                              isThreeLine: true,
                              trailing: user.userId == widget.user.userId
                                  ? const Chip(label: Text('Tú'))
                                  : PopupMenuButton<String>(
                                      enabled: _busyId == null,
                                      tooltip: 'Acciones de miembro',
                                      onSelected: (value) {
                                        if (value == 'admin') {
                                          _setRole(user, UserRole.admin);
                                        } else if (value == 'vecino') {
                                          _setRole(user, UserRole.vecino);
                                        } else if (value == 'remove') {
                                          _remove(user);
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        if (user.isNeighbor)
                                          const PopupMenuItem(
                                            value: 'admin',
                                            child: Text('Hacer administrador'),
                                          ),
                                        if (user.isAdmin)
                                          const PopupMenuItem(
                                            value: 'vecino',
                                            child: Text('Cambiar a vecino'),
                                          ),
                                        if (user.isNeighbor)
                                          const PopupMenuItem(
                                            value: 'remove',
                                            child: Text('Retirar acceso'),
                                          ),
                                      ],
                                    )));
                    });
              },
            ),
          ]),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 64),
        const SizedBox(height: 10),
        Text(text)
      ]));
}
