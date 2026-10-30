import '../../widgets/limited_text_form_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';
import '../../services/file_service.dart';
import '../../services/access_request_document_picker.dart';
import '../../widgets/access_request_documents_section.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key, this.pickDocument, this.submitRequest});

  final Future<SelectedUpload?> Function(AccessDocumentSource source)?
      pickDocument;
  final Future<String> Function(
      {required String name,
      required String dni,
      required String phone,
      required String email,
      required String address,
      required String timeLivingHere,
      required String reason,
      required List<SelectedUpload> identityDocuments})? submitRequest;
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
  List<SelectedUpload> _identityDocuments = [];
  bool _loading = false;

  @override
  void dispose() {
    for (final controller in [_name, _dni, _phone, _email, _address, _reason]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_identityDocuments.isEmpty) {
      _message('Adjunta un documento de respaldo.', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final requestId = await (widget.submitRequest ??
          AuthService.instance.submitAccessRequest)(
        name: _name.text,
        dni: _dni.text,
        phone: _phone.text,
        email: _email.text,
        address: _address.text,
        timeLivingHere: _timeLiving!,
        reason: _reason.text,
        identityDocuments: List.unmodifiable(_identityDocuments),
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
                          LimitedTextFormField(
                              characterLimit: 160,
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
                          LimitedTextFormField(
                            characterLimit: 320,
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
                          LimitedTextFormField(
                              characterLimit: 300,
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
                          LimitedTextFormField(
                              characterLimit: 1000,
                              controller: _reason,
                              minLines: 3,
                              maxLines: 5,
                              decoration: const InputDecoration(
                                  labelText: 'Motivo de la solicitud'),
                              validator: _required),
                          const SizedBox(height: 18),
                          AccessRequestDocumentsSection(
                            documents: _identityDocuments,
                            enabled: !_loading,
                            pick: widget.pickDocument,
                            onChanged: (files) =>
                                setState(() => _identityDocuments = files),
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
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                  'Al enviar tu solicitud, aceptas las normas de convivencia de la comunidad.',
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
