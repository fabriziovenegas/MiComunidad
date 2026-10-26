import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';
import '../../services/file_service.dart';
import '../../widgets/upload_picker.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _dni = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _reason = TextEditingController();
  String? _timeLiving;
  SelectedUpload? _identityDocument;
  bool _loading = false;

  @override
  void dispose() {
    for (final controller in [_name, _dni, _phone, _email, _address, _reason]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDocument() async {
    final selected =
        await pickUploadWithFeedback(context, FileService.pickIdentityDocument);
    if (selected != null && mounted) {
      setState(() => _identityDocument = selected);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_identityDocument == null) {
      _message('Adjunta tu documento de identidad.', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final requestId = await AuthService.instance.submitAccessRequest(
        name: _name.text,
        dni: _dni.text,
        phone: _phone.text,
        email: _email.text,
        address: _address.text,
        timeLivingHere: _timeLiving!,
        reason: _reason.text,
        identityDocument: _identityDocument!,
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        '/request-success',
        arguments: {
          'requestId': requestId,
          'name': _name.text.trim(),
          'email': _email.text.trim(),
          'dni': _dni.text.trim(),
        },
      );
    } catch (error) {
      _message(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String value, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(value),
          backgroundColor: error ? Theme.of(context).colorScheme.error : null),
    );
  }

  String _friendlyError(Object error) {
    if (error is AuthFlowException) return error.message;
    return 'No pudimos completar la acción. Inténtalo nuevamente.';
  }

  String? _required(String? value) => value == null || value.trim().isEmpty
      ? 'Este campo es obligatorio.'
      : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Solicitud de ingreso')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 650),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                              'Completa tus datos para unirte a la Junta Vecinal.',
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 6),
                          const Text(
                              'Todos los campos son obligatorios. El administrador revisará la solicitud.'),
                          const SizedBox(height: 24),
                          TextFormField(
                              controller: _name,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                  labelText: 'Nombre completo',
                                  hintText: 'Escribe tus nombres y apellidos'),
                              validator: _required),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _dni,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(8)
                            ],
                            decoration: const InputDecoration(
                                labelText: 'DNI (8 dígitos)',
                                hintText: '00000000'),
                            validator: (value) => value?.length == 8
                                ? null
                                : 'El DNI debe tener 8 dígitos.',
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _phone,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(9)
                            ],
                            decoration: const InputDecoration(
                                labelText: 'Teléfono', hintText: '000000000'),
                            validator: (value) => value?.length == 9
                                ? null
                                : 'El teléfono debe tener 9 dígitos.',
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                                labelText: 'Correo electrónico',
                                hintText: 'correo@example.com'),
                            validator: (value) => value != null &&
                                    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                        .hasMatch(value.trim())
                                ? null
                                : 'Ingresa un correo válido.',
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                              controller: _address,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                  labelText: 'Dirección exacta'),
                              validator: _required),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            initialValue: _timeLiving,
                            decoration: const InputDecoration(
                                labelText: 'Tiempo viviendo aquí'),
                            items: const [
                              'Menos de 1 año',
                              '1 a 5 años',
                              '5 a 10 años',
                              'Más de 10 años'
                            ]
                                .map((value) => DropdownMenuItem(
                                    value: value, child: Text(value)))
                                .toList(),
                            onChanged: (value) =>
                                setState(() => _timeLiving = value),
                            validator: (value) =>
                                value == null ? 'Selecciona una opción.' : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                              controller: _reason,
                              minLines: 3,
                              maxLines: 5,
                              decoration: const InputDecoration(
                                  labelText: 'Motivo de la solicitud'),
                              validator: _required),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                                  .withValues(alpha: .45),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.verified_user_outlined),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Este archivo permite confirmar que perteneces a la comunidad. Adjunta un recibo de agua de tu vivienda o una foto legible de tu DNI.',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Semantics(
                            button: true,
                            label: 'Adjuntar documento de identidad',
                            child: InkWell(
                              onTap: _loading ? null : _pickDocument,
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.all(22),
                                decoration: BoxDecoration(
                                    border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outlineVariant,
                                        width: 2),
                                    borderRadius: BorderRadius.circular(16)),
                                child: Column(
                                  children: [
                                    const Icon(Icons.upload_file, size: 42),
                                    const SizedBox(height: 8),
                                    Text(_identityDocument?.name ??
                                        'Toca para adjuntar tu documento'),
                                    const Text('JPG, JPEG, PNG, WEBP o PDF · máximo 5 MB'),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          FilledButton.icon(
                            onPressed: _loading ? null : _submit,
                            icon: _loading
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.send),
                            label: Text(
                                _loading ? 'Enviando…' : 'Enviar solicitud'),
                          ),
                          TextButton(
                              onPressed: _loading
                                  ? null
                                  : () => Navigator.pop(context),
                              child: const Text('Volver atrás')),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                  'Al enviar esta solicitud, aceptas los términos de convivencia de la junta vecinal.',
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
