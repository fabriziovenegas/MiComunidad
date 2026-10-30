import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/upload_connection.dart';
import 'form_submission_guard.dart';
import 'limited_text_form_field.dart';

class MapPointForm extends StatefulWidget {
  const MapPointForm({super.key, required this.onSave, this.isOffline});
  final Future<void> Function(String title, String description) onSave;
  final Future<bool> Function()? isOffline;
  @override
  State<MapPointForm> createState() => _MapPointFormState();
}

class _MapPointFormState extends State<MapPointForm> {
  final _form = GlobalKey<FormState>();
  String _title = '', _description = '';
  @override
  Widget build(BuildContext context) => FormSubmissionGuard(
        slowAfter: const Duration(seconds: 10),
        validate: () => _form.currentState?.validate() == true,
        errorMessage: (error) => error is FirebaseException &&
                error.code == 'unavailable'
            ? 'Necesitas conexión para guardar el punto'
            : 'No se pudo guardar el punto. Tus datos se conservan. Intenta nuevamente.',
        onSubmit: () async {
          if (await (widget.isOffline ?? UploadConnection.isOffline)()) {
            throw FirebaseException(
                plugin: 'cloud_firestore', code: 'unavailable');
          }
          await widget.onSave(_title.trim(), _description.trim());
        },
        onSubmitted: (context) => Navigator.pop(context, true),
        builder: (context, saving, submit) => AlertDialog(
          title: const Text('Nuevo punto comunitario'),
          content: SingleChildScrollView(
              child: Form(
                  key: _form,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    LimitedTextFormField(
                        characterLimit: 160,
                        enabled: !saving,
                        onChanged: (value) => _title = value,
                        decoration: const InputDecoration(labelText: 'Nombre'),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'El nombre es obligatorio.'
                                : null),
                    const SizedBox(height: 10),
                    LimitedTextFormField(
                        characterLimit: 4000,
                        enabled: !saving,
                        onChanged: (value) => _description = value,
                        decoration:
                            const InputDecoration(labelText: 'Descripción')),
                  ]))),
          actions: [
            TextButton(
                onPressed: saving && !FormSubmissionGuard.isTakingLong(context)
                    ? null
                    : () => Navigator.pop(context, false),
                child: Text(saving ? 'Cerrar' : 'Cancelar')),
            FilledButton(
                onPressed: saving ? null : submit,
                child: Text(saving
                    ? (FormSubmissionGuard.isTakingLong(context)
                        ? 'Esperando confirmación…'
                        : 'Guardando…')
                    : 'Guardar')),
          ],
        ),
      );
}
