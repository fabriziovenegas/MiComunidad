import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Uses the existing private agenda, with the same earliest-future-event query
/// used by the resident dashboard. No public summary or new backend is needed.
class AdminUpcomingEventCard extends StatefulWidget {
  const AdminUpcomingEventCard(
      {super.key,
      required this.firestore,
      required this.onOpenAgenda,
      this.now});
  final FirebaseFirestore firestore;
  final VoidCallback onOpenAgenda;
  final DateTime Function()? now;
  @override
  State<AdminUpcomingEventCard> createState() => _AdminUpcomingEventCardState();
}

class _AdminUpcomingEventCardState extends State<AdminUpcomingEventCard> {
  late Stream<QuerySnapshot<Map<String, dynamic>>> _events;
  Timer? _expiry;
  DateTime? _scheduledFor;
  DateTime _now() => (widget.now ?? DateTime.now)();
  Stream<QuerySnapshot<Map<String, dynamic>>> _query() => widget.firestore
      .collection('events')
      .where('eventDate', isGreaterThanOrEqualTo: Timestamp.fromDate(_now()))
      .orderBy('eventDate')
      .limit(1)
      .snapshots();
  @override
  void initState() {
    super.initState();
    _events = _query();
  }

  @override
  void didUpdateWidget(covariant AdminUpcomingEventCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.firestore != widget.firestore) {
      _expiry?.cancel();
      _scheduledFor = null;
      _events = _query();
    }
  }

  void _schedule(DateTime? date) {
    if (date == _scheduledFor) return;
    _expiry?.cancel();
    _scheduledFor = date;
    if (date == null) return;
    final delay = date.difference(_now()) + const Duration(milliseconds: 1);
    _expiry = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (!mounted) return;
      setState(() {
        _scheduledFor = null;
        _events = _query();
      });
    });
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<
          QuerySnapshot<Map<String, dynamic>>>(
      stream: _events,
      builder: (context, snapshot) {
        final data = snapshot.data?.docs.firstOrNull?.data();
        final date = data?['eventDate'] is Timestamp
            ? (data!['eventDate'] as Timestamp).toDate().toLocal()
            : null;
        // A replacement stream briefly retains the previous snapshot. Do not
        // schedule another immediate refresh from that expired cached value.
        if (snapshot.connectionState == ConnectionState.active) {
          _schedule(snapshot.hasError ? null : date);
        }
        final hasEvent = !snapshot.hasError && data != null && date != null;
        final title = snapshot.hasError
            ? 'No se pudo consultar la agenda'
            : !snapshot.hasData
                ? 'Consultando agenda…'
                : !hasEvent
                    ? 'No hay reuniones próximas'
                    : (data['title'] as String?)?.trim().isNotEmpty == true
                        ? data['title'] as String
                        : 'Actividad de la comunidad';
        final location = (data?['location'] as String?)?.trim() ?? '';
        return Material(
            color: const Color(0xFFEBF5EE),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: Color(0xFF91B89D))),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onOpenAgenda,
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (hasEvent)
                          _EventDate(date: date)
                        else
                          const Icon(Icons.event_available_outlined,
                              color: Color(0xFF276749), size: 30),
                        if (hasEvent)
                          Container(
                              width: 1,
                              height: 60,
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              color: const Color(0xFFBCD2C3))
                        else
                          const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: const Color(0xFFD0ECD8),
                                      borderRadius: BorderRadius.circular(8)),
                                  child: Text('Próxima reunión',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFF245F45)))),
                              const SizedBox(height: 4),
                              Text(title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              if (hasEvent) ...[
                                _MeetingMetadata(
                                    date: date, location: location),
                              ] else
                                Text(
                                    snapshot.hasError
                                        ? 'Abre la agenda para intentarlo de nuevo.'
                                        : 'Consulta las actividades de la comunidad.',
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                            ])),
                        const SizedBox(width: 6),
                        const Icon(Icons.chevron_right,
                            color: Color(0xFF276749)),
                      ])),
            ));
      });
}

class _EventDate extends StatelessWidget {
  const _EventDate({required this.date});
  final DateTime date;
  static const months = [
    'ENE',
    'FEB',
    'MAR',
    'ABR',
    'MAY',
    'JUN',
    'JUL',
    'AGO',
    'SEP',
    'OCT',
    'NOV',
    'DIC'
  ];
  @override
  Widget build(BuildContext context) => Semantics(
      label: '${date.day}/${date.month}/${date.year}',
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
              width: 56,
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF276749))),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    height: 14,
                    decoration: const BoxDecoration(
                        color: Color(0xFF27834A),
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(9)))),
                Padding(
                    padding: const EdgeInsets.fromLTRB(4, 3, 4, 0),
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('${date.day}',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF18241E))))),
                Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 3),
                    child: FittedBox(
                        child: Text(months[date.month - 1],
                            style: Theme.of(context).textTheme.labelSmall))),
              ])),
          for (final left in [13.0, 39.0])
            Positioned(
                left: left,
                top: -4,
                child: Container(
                    width: 4,
                    height: 12,
                    decoration: BoxDecoration(
                        color: const Color(0xFF276749),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: Colors.white, width: .6)))),
        ]),
      ));
}

class _MeetingMetadata extends StatelessWidget {
  const _MeetingMetadata({required this.date, required this.location});
  final DateTime date;
  final String location;

  @override
  Widget build(BuildContext context) {
    final time =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} h';
    final timeWidget =
        _EventMetadata(icon: Icons.schedule_outlined, text: time);
    if (location.isEmpty) return timeWidget;
    final locationWidget =
        _EventMetadata(icon: Icons.location_on_outlined, text: location);
    return LayoutBuilder(builder: (context, constraints) {
      double textWidth(String text) {
        final painter = TextPainter(
            text: TextSpan(
                text: text, style: Theme.of(context).textTheme.bodySmall),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context))
          ..layout();
        final width = painter.width;
        painter.dispose();
        return width;
      }

      final timeWidth = textWidth(time) + 22;
      if (timeWidth + textWidth(location) + 47 <= constraints.maxWidth) {
        return Row(children: [
          SizedBox(width: timeWidth, child: timeWidget),
          Container(
              width: 1,
              height: 14,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              color: const Color(0xFFBCD2C3)),
          Expanded(child: locationWidget),
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        timeWidget,
        const SizedBox(height: 2),
        locationWidget,
      ]);
    });
  }
}

class _EventMetadata extends StatelessWidget {
  const _EventMetadata({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: const Color(0xFF63746A)),
        const SizedBox(width: 6),
        Expanded(
            child: Text(text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: const Color(0xFF526258)))),
      ]);
}
