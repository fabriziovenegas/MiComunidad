import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/project_dates.dart';

class ProjectDatesFields extends StatefulWidget {
  const ProjectDatesFields(
      {super.key,
      this.start,
      this.end,
      required this.enabled,
      required this.onChanged});
  final DateTime? start, end;
  final bool enabled;
  final void Function(DateTime?, DateTime?) onChanged;
  @override
  State<ProjectDatesFields> createState() => _ProjectDatesFieldsState();
}

class _ProjectDatesFieldsState extends State<ProjectDatesFields> {
  bool _picking = false;
  bool _expanded = false;
  Widget field(String label, DateTime? date, bool start) =>
      FormField<DateTime?>(
          initialValue: date,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (_) => widget.start != null &&
                  widget.end != null &&
                  widget.end!.isBefore(widget.start!)
              ? 'La finalización no puede ser anterior al inicio.'
              : null,
          builder: (state) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: InputDecorator(
                    decoration: InputDecoration(
                        labelText: '$label (opcional)',
                        errorText: state.errorText,
                        errorMaxLines: 3),
                    child: Row(children: [
                      Expanded(
                          child: InkWell(
                        onTap: !widget.enabled || _picking
                            ? null
                            : () async {
                                setState(() => _picking = true);
                                try {
                                  final initial = date ?? DateTime.now();
                                  final selected = await showDatePicker(
                                      context: context,
                                      initialDate: initial,
                                      firstDate: DateTime(initial.year < 1900
                                          ? initial.year
                                          : 1900),
                                      lastDate: DateTime(initial.year > 2100
                                          ? initial.year + 1
                                          : 2101));
                                  if (!mounted || selected == null) return;
                                  state.didChange(selected);
                                  widget.onChanged(
                                      start ? selected : widget.start,
                                      start ? widget.end : selected);
                                } finally {
                                  if (mounted) setState(() => _picking = false);
                                }
                              },
                        child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Text(date == null
                                ? 'Seleccionar fecha'
                                : DateFormat('dd/MM/yyyy').format(date))),
                      )),
                      if (date != null)
                        IconButton(
                            tooltip: 'Quitar $label',
                            onPressed: !widget.enabled || _picking
                                ? null
                                : () {
                                    state.didChange(null);
                                    widget.onChanged(
                                        start ? null : widget.start,
                                        start ? widget.end : null);
                                  },
                            icon: const Icon(Icons.close)),
                      const Icon(Icons.calendar_today_outlined, size: 20),
                    ])),
              ));
  @override
  Widget build(BuildContext context) {
    final summary = <String>[
      if (widget.start != null)
        'Inicio: ${DateFormat('dd/MM/yyyy').format(widget.start!)}',
      if (widget.end != null)
        'Fin previsto: ${DateFormat('dd/MM/yyyy').format(widget.end!)}',
    ];
    final invalid = widget.start != null &&
        widget.end != null &&
        widget.end!.isBefore(widget.start!);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Semantics(
          expanded: _expanded,
          child: InkWell(
            onTap: !widget.enabled || _picking
                ? null
                : () => setState(() => _expanded = !_expanded),
            child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  const Icon(Icons.date_range_outlined, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('Fechas del proyecto',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(summary.isEmpty ? 'Opcional' : summary.join(' · '),
                            style: Theme.of(context).textTheme.bodySmall),
                      ])),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ])),
          )),
      if (!_expanded && invalid)
        Text('La finalización no puede ser anterior al inicio.',
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      // Keep validators and selected values alive even when folded.
      Offstage(
          offstage: !_expanded,
          child: Column(children: [
            field('Inicio', widget.start, true),
            field('Fin previsto', widget.end, false),
          ])),
    ]);
  }
}

class ProjectDatesSummary extends StatelessWidget {
  const ProjectDatesSummary({super.key, required this.data});
  final Map<String, dynamic> data;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Fechas del proyecto',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                )),
        for (final entry in [
          ('Inicio', 'startDate'),
          ('Fin previsto', 'expectedEndDate')
        ])
          if (ProjectDates.date(data[entry.$2]) case final DateTime date)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      entry.$2 == 'startDate'
                          ? Icons.event_available_outlined
                          : Icons.event_outlined,
                      size: 22,
                      color: const Color(0xFF276749),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${entry.$1}: ${DateFormat('dd/MM/yyyy').format(date)}',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: const Color(0xFF515B55),
                            ),
                      ),
                    ),
                  ],
                )),
      ]);
}
