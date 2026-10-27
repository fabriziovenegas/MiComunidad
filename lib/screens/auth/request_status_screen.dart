import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../services/auth_service.dart';
import '../../utils/email_privacy.dart';

class RequestStatusScreen extends StatefulWidget {
  const RequestStatusScreen({
    super.key,
    this.initialDni,
    this.initialRequest,
  });

  /// Valores opcionales usados por pruebas y capturas de interfaz.
  /// En la aplicación normal la consulta continúa realizándose mediante DNI.
  final String? initialDni;
  final Map<String, dynamic>? initialRequest;

  @override
  State<RequestStatusScreen> createState() => _RequestStatusScreenState();
}

class _RequestStatusScreenState extends State<RequestStatusScreen> {
  final _dni = TextEditingController();
  Map<String, dynamic>? _request;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _dni.text = widget.initialDni ?? '';
    if (widget.initialRequest != null) {
      _request = Map<String, dynamic>.from(widget.initialRequest!);
    }
  }

  @override
  void dispose() {
    _dni.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_dni.text.length != 8) {
      setState(() => _error = 'Ingresa un DNI de 8 dígitos.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _request = null;
    });
    try {
      final result = await AuthService.instance.findRequestStatus(_dni.text);
      if (mounted) {
        setState(() => result == null
            ? _error = 'No encontramos una solicitud con ese DNI.'
            : _request = result);
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'No se pudo consultar el estado. Inténtalo nuevamente.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Estado de solicitud')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.badge_outlined),
                        SizedBox(width: 12),
                        Expanded(
                            child: Text(
                                'Ingresa tu DNI para consultar el progreso de tu solicitud de ingreso.'))
                      ]),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _dni,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(8)
                    ],
                    onSubmitted: (_) => _search(),
                    decoration: InputDecoration(
                        labelText: 'DNI (8 dígitos)',
                        suffixIcon: IconButton(
                            onPressed: _dni.clear,
                            icon: const Icon(Icons.clear))),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                      onPressed: _loading ? null : _search,
                      icon: const Icon(Icons.search),
                      label:
                          Text(_loading ? 'Consultando…' : 'Consultar estado')),
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                ],
              ),
            ),
          ),
          if (_request != null) ...[
            const SizedBox(height: 16),
            _StatusCard(request: _request!),
            const SizedBox(height: 16),
            _ApprovalRoute(
                status: _request!['status'] as String? ?? 'pendiente'),
            const SizedBox(height: 16),
            // Card(
            //   child: ListTile(
            //     leading: const Icon(Icons.support_agent),
            //     title: const Text('¿Necesitas ayuda?'),
            //     subtitle: const Text(
            //         'Contacta a la junta desde tu aplicación de correo.'),
            //     trailing: OutlinedButton(
            //       onPressed: () => launchUrl(
            //         Uri(
            //           scheme: 'mailto',
            //           queryParameters: {
            //             'subject':
            //                 'Consulta sobre solicitud ${AppIdentity.appName}'
            //           },
            //         ),
            //       ),
            //       child: const Text('Contactar'),
            //     ),
            //   ),
            // ),
          ],
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.request});
  final Map<String, dynamic> request;

  @override
  Widget build(BuildContext context) {
    final status = request['status'] as String? ?? 'pendiente';
    final color = switch (status) {
      'aprobado' => Colors.green,
      'rechazado' => Theme.of(context).colorScheme.error,
      'retirado' => Theme.of(context).colorScheme.outline,
      _ => Colors.amber.shade800,
    };
    final icon = switch (status) {
      'aprobado' => Icons.check_circle,
      'rechazado' => Icons.cancel,
      'retirado' => Icons.person_off_outlined,
      _ => Icons.hourglass_top,
    };
    final title = switch (status) {
      'aprobado' => 'Aprobado',
      'rechazado' => 'Rechazado',
      'retirado' => 'Acceso retirado',
      _ => 'En revisión'
    };
    final rawDate = request['createdAt'] as String? ?? '';
    final parsedDate = DateTime.tryParse(rawDate)?.toLocal();
    final date = parsedDate == null
        ? 'Pendiente de sincronización'
        : DateFormat('dd/MM/yyyy HH:mm').format(parsedDate);
    final email = maskPublicEmail(request['email']);
    return Card(
      color: color.withValues(alpha: .10),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 64, color: color),
            const SizedBox(height: 12),
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 8),
            Text(
              status == 'aprobado'
                  ? 'Tu cuenta fue habilitada. Revisa tu correo para establecer la contraseña.'
                  : status == 'rechazado'
                      ? 'La solicitud no fue aprobada.'
                      : status == 'retirado'
                          ? 'Tu acceso anterior fue retirado. Puedes enviar una nueva solicitud de ingreso.'
                          : 'El administrador está verificando tus datos.',
              textAlign: TextAlign.center,
            ),
            const Divider(height: 32),
            ListTile(title: const Text('Fecha de envío'), trailing: Text(date)),
            ListTile(
                title: const Text('Correo electrónico'),
                subtitle: Text(email.isEmpty ? 'No disponible' : email)),
          ],
        ),
      ),
    );
  }
}

class _ApprovalRoute extends StatelessWidget {
  const _ApprovalRoute({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final decided =
        status == 'aprobado' || status == 'rechazado' || status == 'retirado';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ruta de aprobación',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            const _RouteStep(
              icon: Icons.check_circle,
              title: 'Solicitud recibida',
              detail: 'Los datos y el documento quedaron registrados.',
              completed: true,
            ),
            _RouteStep(
              icon: decided ? Icons.check_circle : Icons.hourglass_top,
              title: 'Revisión administrativa',
              detail: decided
                  ? 'La revisión finalizó.'
                  : 'El administrador está verificando la información.',
              completed: decided,
              active: !decided,
            ),
            _RouteStep(
              icon: status == 'rechazado' ? Icons.cancel : Icons.verified,
              title: 'Decisión final',
              detail: status == 'aprobado'
                  ? 'Solicitud aprobada.'
                  : status == 'rechazado'
                      ? 'Solicitud no aprobada.'
                      : status == 'retirado'
                          ? 'Acceso anterior retirado. Puedes solicitar ingreso nuevamente.'
                          : 'Pendiente de decisión.',
              completed: decided,
              rejected: status == 'rechazado',
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteStep extends StatelessWidget {
  const _RouteStep({
    required this.icon,
    required this.title,
    required this.detail,
    required this.completed,
    this.active = false,
    this.rejected = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool completed;
  final bool active;
  final bool rejected;

  @override
  Widget build(BuildContext context) {
    final color = rejected
        ? Theme.of(context).colorScheme.error
        : completed
            ? Colors.green
            : active
                ? Colors.amber.shade800
                : Theme.of(context).colorScheme.outline;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(detail),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
