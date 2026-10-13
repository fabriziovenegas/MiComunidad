import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../config/community_map_data.dart';
import '../../models/user_model.dart';
import '../../utils/text_encoding.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.user});
  final AppUser user;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _mapController = MapController();
  _CommunityMapStyle _style = _CommunityMapStyle.streets;

  Future<void> _addPoint(BuildContext context, LatLng point) async {
    if (!widget.user.isAdmin) return;
    var title = '';
    var description = '';
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuevo punto comunitario'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              onChanged: (value) => title = value,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 10),
            TextField(
              onChanged: (value) => description = value,
              decoration: const InputDecoration(labelText: 'Descripción'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (save == true && title.trim().isNotEmpty) {
      await FirebaseFirestore.instance.collection('mapPoints').add({
        'title': title.trim(),
        'description': description.trim(),
        'latitude': point.latitude,
        'longitude': point.longitude,
        'createdBy': widget.user.userId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  void _showPoint(BuildContext context, String title, String description) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(description),
          ],
        ),
      ),
    );
  }

  void _resetView() => _mapController.fitCamera(
        CameraFit.bounds(
          bounds: CommunityMapData.viewBounds,
          padding: const EdgeInsets.fromLTRB(28, 175, 28, 50),
          maxZoom: 16.8,
        ),
      );

  void _keepInsideCommunity(MapCamera camera, bool hasGesture) {
    if (!hasGesture || CommunityMapData.viewBounds.contains(camera.center)) {
      return;
    }
    final bounds = CommunityMapData.viewBounds;
    final corrected = LatLng(
      camera.center.latitude.clamp(bounds.south, bounds.north),
      camera.center.longitude.clamp(bounds.west, bounds.east),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.move(corrected, camera.zoom);
    });
  }

  Future<void> _openGoogleMaps() => launchUrl(
        Uri.parse(CommunityMapData.googleMapsUrl),
        mode: LaunchMode.externalApplication,
      );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('mapPoints').snapshots(),
      builder: (context, snapshot) {
        final dynamicMarkers =
            (snapshot.data?.docs ?? const []).map((document) {
          final data = document.data();
          final title = readableText(data['title']);
          final description = readableText(data['description']);
          return Marker(
            point: LatLng(
              (data['latitude'] as num).toDouble(),
              (data['longitude'] as num).toDouble(),
            ),
            width: 44,
            height: 44,
            child: GestureDetector(
              onTap: () => _showPoint(context, title, description),
              child:
                  const Icon(Icons.location_pin, size: 42, color: Colors.red),
            ),
          );
        });

        final landmarkMarkers = CommunityMapData.landmarks.map((landmark) {
          return Marker(
            point: landmark.point,
            width: 42,
            height: 42,
            child: GestureDetector(
              onTap: () => _showPoint(
                context,
                landmark.name,
                landmark.description,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 4),
                  ],
                ),
                child: Icon(
                  _landmarkIcon(landmark.icon),
                  size: 24,
                  color: AppColors.primary,
                ),
              ),
            ),
          );
        });

        return Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCameraFit: CameraFit.bounds(
                  bounds: CommunityMapData.viewBounds,
                  padding: const EdgeInsets.fromLTRB(24, 165, 24, 42),
                  maxZoom: 16.8,
                ),
                minZoom: 14.7,
                maxZoom: _style.maxZoom,
                onPositionChanged: _keepInsideCommunity,
                onLongPress: widget.user.isAdmin
                    ? (position, point) => _addPoint(context, point)
                    : null,
              ),
              children: [
                TileLayer(
                  urlTemplate: _style.urlTemplate,
                  subdomains: _style.subdomains,
                  userAgentPackageName: 'app.micomunidad',
                  maxZoom: _style.maxZoom,
                ),
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: CommunityMapData.communityBoundary,
                      color: const Color(0x33006D43),
                      borderColor: AppColors.primary,
                      borderStrokeWidth: 3,
                    ),
                  ],
                ),
                MarkerLayer(markers: [...landmarkMarkers, ...dynamicMarkers]),
              ],
            ),
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.map_outlined),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<_CommunityMapStyle>(
                                isExpanded: true,
                                value: _style,
                                items: _CommunityMapStyle.values
                                    .map(
                                      (style) => DropdownMenuItem(
                                        value: style,
                                        child: Text(style.label),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() => _style = value);
                                  }
                                },
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Centrar comunidad',
                            onPressed: _resetView,
                            icon: const Icon(Icons.center_focus_strong),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.user.isAdmin
                                  ? 'Mantén pulsado para añadir una referencia.'
                                  : 'Área delimitada según el plano proporcionado.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _openGoogleMaps,
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('Google Maps'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 6,
              right: 6,
              child: Material(
                color: Colors.white.withValues(alpha: .85),
                borderRadius: BorderRadius.circular(4),
                child: InkWell(
                  onTap: () => launchUrl(Uri.parse(_style.attributionUrl)),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(_style.attribution,
                        style: const TextStyle(fontSize: 9)),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

IconData _landmarkIcon(CommunityLandmarkIcon icon) => switch (icon) {
      CommunityLandmarkIcon.transport => Icons.directions_bus,
      CommunityLandmarkIcon.religion => Icons.church_outlined,
      CommunityLandmarkIcon.community => Icons.groups_outlined,
      CommunityLandmarkIcon.shop => Icons.storefront_outlined,
      CommunityLandmarkIcon.sports => Icons.sports_soccer,
      CommunityLandmarkIcon.bank => Icons.account_balance_outlined,
    };

enum _CommunityMapStyle {
  streets(
    label: 'Calles (OpenStreetMap)',
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    subdomains: [],
    maxZoom: 19,
    attribution: '© OpenStreetMap contributors',
    attributionUrl: 'https://www.openstreetmap.org/copyright',
  ),
  terrain(
    label: 'Relieve (OpenTopoMap)',
    urlTemplate: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
    subdomains: ['a', 'b', 'c'],
    maxZoom: 17,
    attribution: '© OpenStreetMap · OpenTopoMap',
    attributionUrl: 'https://opentopomap.org/about',
  );

  const _CommunityMapStyle({
    required this.label,
    required this.urlTemplate,
    required this.subdomains,
    required this.maxZoom,
    required this.attribution,
    required this.attributionUrl,
  });

  final String label;
  final String urlTemplate;
  final List<String> subdomains;
  final double maxZoom;
  final String attribution;
  final String attributionUrl;
}
