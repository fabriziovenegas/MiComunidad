import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'community_config.dart';

/// Build-time geometry. Default coordinates are synthetic and in the ocean.
class CommunityMapData {
  CommunityMapData._();
  static LatLng _point(dynamic value) {
    final coordinates = (value as List).cast<num>();
    if (coordinates.length != 2 ||
        !coordinates.every((value) => value.isFinite) ||
        coordinates[0].abs() > 90 ||
        coordinates[1].abs() > 180) {
      throw const FormatException('Invalid map coordinates.');
    }
    return LatLng(coordinates[0].toDouble(), coordinates[1].toDouble());
  }

  static final googleMapsReference = _point(CommunityConfig.map['reference']);
  static final communityCenter = _point(CommunityConfig.map['center']);
  static final viewBounds = LatLngBounds(
      _point(CommunityConfig.map['bounds'][0]),
      _point(CommunityConfig.map['bounds'][1]));
  static final googleMapsUrl = CommunityConfig.map['url'] as String;
  static final landmarks = List<CommunityLandmark>.unmodifiable((CommunityConfig
          .map['landmarks'] as List)
      .map((value) => CommunityLandmark(
          name: value['name'] as String,
          description: value['description'] as String,
          point: _point(value['point']),
          icon: CommunityLandmarkIcon.values.byName(value['icon'] as String))));
  static final communityBoundary = List<LatLng>.unmodifiable(
      (CommunityConfig.map['boundary'] as List).map(_point));
}

enum CommunityLandmarkIcon {
  transport,
  religion,
  community,
  shop,
  sports,
  bank
}

class CommunityLandmark {
  const CommunityLandmark(
      {required this.name,
      required this.description,
      required this.point,
      required this.icon});
  final String name;
  final String description;
  final LatLng point;
  final CommunityLandmarkIcon icon;
}
