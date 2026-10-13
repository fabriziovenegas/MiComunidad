import 'package:flutter/material.dart';

class RequestSuccessScreen extends StatelessWidget {
  const RequestSuccessScreen({super.key, required this.summary});
  final Map<String, String> summary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: .55),
              Theme.of(context).colorScheme.surface
            ],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(28),
            children: [
              const SizedBox(height: 30),
              Icon(Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary, size: 112),
              const SizedBox(height: 18),
              Text('¡Solicitud enviada con éxito!',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text(
                  'El administrador recibirá tu solicitud y revisará la información adjunta.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 28),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          _row('Nombre', summary['name'] ?? ''),
                          const Divider(),
                          _row('DNI', summary['dni'] ?? ''),
                          const Divider(),
                          _row('Correo', summary['email'] ?? ''),
                          const Divider(),
                          _row('Código', summary['requestId'] ?? ''),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                  onPressed: () =>
                      Navigator.popUntil(context, (route) => route.isFirst),
                  child: const Text('Ir al inicio')),
              const SizedBox(height: 12),
              OutlinedButton(
                  onPressed: () => Navigator.pushReplacementNamed(
                      context, '/request-status'),
                  child: const Text('Ver estado de mi solicitud')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 90,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: Text(value, textAlign: TextAlign.end)),
        ],
      );
}
