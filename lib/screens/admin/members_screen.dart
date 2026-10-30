import '../../widgets/limited_text_form_field.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/access_request_document_links.dart';
import '../../models/access_request.dart';
import '../../models/user_model.dart';
import '../../services/community_service.dart';
import '../../services/access_request_review.dart';
import '../../widgets/access_request_details.dart';
import '../../widgets/access_request_preview_card.dart';
import '../../widgets/member_details_sheet.dart';

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

  bool _canApprove(AccessRequest request) => canReviewAccessRequest(
      isAdmin: widget.user.isAdmin, status: request.status);

  bool _canReject(AccessRequest request) => canReviewAccessRequest(
      isAdmin: widget.user.isAdmin, status: request.status);
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
      final reasonForm = GlobalKey<FormState>();
      var inputReason = '';
      reason = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('Rechazar solicitud'),
                  content: Form(
                      key: reasonForm,
                      child: LimitedTextFormField(
                          characterLimit: 1000,
                          onChanged: (value) => inputReason = value,
                          maxLines: 3,
                          decoration: const InputDecoration(
                              labelText: 'Motivo del rechazo',
                              labelStyle:
                                  TextStyle(fontWeight: FontWeight.bold),
                              helperText:
                                  'El motivo quedará registrado internamente.',
                              helperMaxLines: 3))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: () {
                          if (reasonForm.currentState!.validate()) {
                            Navigator.pop(context, inputReason);
                          }
                        },
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
      final result = await reviewAccessRequestWithEmail(
        approve: approve,
        review: () => CommunityService.instance.reviewAccessRequest(
            requestId: request.id, approve: approve, reason: reason),
        sendEmail: () =>
            FirebaseAuth.instance.sendPasswordResetEmail(email: request.email),
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.message)));
      }
    } catch (error) {
      if (mounted) {
        final message = accessRequestReviewErrorMessage(error,
            approve: approve, status: request.status);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _remove(AppUser user) async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Retirar acceso'),
                content: Text('¿Deseas retirar el acceso de ${user.nombre}? '
                    'Su historial de solicitudes y sus aportes a la comunidad se conservarán.'),
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
                              AccessRequestDetails(request: request),
                              const SizedBox(height: 20),
                              AccessRequestDocumentLinks(request: request),
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
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                      child: Text('Solicitudes de acceso',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                  fontSize: 20, fontWeight: FontWeight.w700)),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        itemCount: requests.length,
                        itemBuilder: (context, index) {
                          final request = requests[index];
                          return AccessRequestPreviewCard(
                            request: request,
                            onOpen: () => _details(request),
                            reviewActions: _canApprove(request) ||
                                    _canReject(request)
                                ? Row(
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
                                        color: const Color(0xFF276749),
                                        onPressed: _busyId == null
                                            ? () => _review(request, true)
                                            : null,
                                        icon: const Icon(Icons.check_circle),
                                      ),
                                    ],
                                  )
                                : null,
                          );
                        },
                      ),
                    ),
                  ],
                );
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
                              onTap: () => showMemberDetailsSheet(context,
                                  viewer: widget.user,
                                  memberId: user.userId,
                                  members: CommunityService.instance.members()),
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
