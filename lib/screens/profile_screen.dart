import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/user_model.dart';
import '../services/community_service.dart';

typedef ProfileSaver = Future<void> Function({
  required String nombre,
  required String dni,
  required String phone,
  required String email,
  required String address,
  required String timeLivingHere,
  required String reason,
});

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.user, this.onSave});
  final AppUser user;
  final ProfileSaver? onSave;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.user.nombre);
  late final _dni = TextEditingController(text: widget.user.dni);
  late final _phone = TextEditingController(text: widget.user.phone ?? '');
  late final _email = TextEditingController(text: widget.user.email);
  late final _address = TextEditingController(text: widget.user.address);
  late final _reason = TextEditingController(text: widget.user.reason);
  late String _timeLivingHere = widget.user.timeLivingHere;
  bool _saving = false;

  static const _standardTimeOptions = <String>[
    'Menos de 1 año',
    '1 a 5 años',
    '5 a 10 años',
    'Más de 10 años',
  ];

  @override
  void dispose() {
    for (final controller in [
      _name,
      _dni,
      _phone,
      _email,
      _address,
      _reason,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await (widget.onSave ?? CommunityService.instance.updateOwnProfile)(
        nombre: _name.text,
        dni: _dni.text,
        phone: _phone.text,
        email: _email.text,
        address: _address.text,
        timeLivingHere: _timeLivingHere,
        reason: _reason.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cambios guardados correctamente.')),
      );
    } catch (error) {
      if (mounted) {
        final message = error is FirebaseFunctionsException
            ? (error.message ??
                'No se pudo guardar el perfil. Inténtalo de nuevo.')
            : 'No se pudo guardar el perfil. Inténtalo de nuevo.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _required(String? value) => value == null || value.trim().isEmpty
      ? 'Este campo es obligatorio.'
      : null;

  String? _requiredWithLimit(String? value, int maxLength) {
    final requiredError = _required(value);
    if (requiredError != null) return requiredError;
    return value!.trim().length <= maxLength
        ? null
        : 'No puede superar los $maxLength caracteres.';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Mi perfil')),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Center(
                child: CircleAvatar(
                  radius: 38,
                  child: Text(widget.user.initials,
                      style: Theme.of(context).textTheme.headlineMedium),
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                enabled: !_saving,
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nombres'),
                validator: (value) => value == null || value.trim().length < 3
                    ? 'Ingresa tu nombre completo.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                enabled: !_saving,
                controller: _dni,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(8),
                ],
                decoration: const InputDecoration(labelText: 'DNI'),
                validator: (value) =>
                    value?.length == 8 ? null : 'El DNI debe tener 8 dígitos.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                enabled: !_saving,
                controller: _phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(9),
                ],
                decoration: const InputDecoration(labelText: 'Teléfono'),
                validator: (value) => value?.length == 9
                    ? null
                    : 'El teléfono debe tener 9 dígitos.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                enabled: !_saving,
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration:
                    const InputDecoration(labelText: 'Correo electrónico'),
                validator: (value) => value != null &&
                        RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                            .hasMatch(value.trim())
                    ? null
                    : 'Ingresa un correo válido.',
              ),
              const SizedBox(height: 20),
              Text(
                'Datos de la comunidad',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextFormField(
                enabled: !_saving,
                controller: _address,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Dirección registrada',
                ),
                validator: (value) => _requiredWithLimit(value, 300),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _timeLivingHere.isEmpty ? null : _timeLivingHere,
                decoration: const InputDecoration(
                  labelText: 'Tiempo en la comunidad',
                ),
                items: <String>{
                  ..._standardTimeOptions,
                  if (_timeLivingHere.isNotEmpty) _timeLivingHere,
                }
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value),
                      ),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (value) => setState(
                          () => _timeLivingHere = value ?? '',
                        ),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                enabled: !_saving,
                controller: _reason,
                minLines: 3,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Motivo de ingreso',
                ),
                validator: (value) => _requiredWithLimit(value, 1000),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Guardando...' : 'Guardar cambios'),
              ),
            ],
          ),
        ),
      );
}
