import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/config/community_config.dart';
import 'package:micomunidad/config/community_map_data.dart';
import 'package:micomunidad/firebase_options.dart';

void main() {
  test('la selección de fotografías corresponde al flavor del build', () {
    if (CommunityConfig.usesPrivateImages) {
      expect(CommunityConfig.heroImage, contains('assets/images/'));
      expect(CommunityConfig.communityImages.toSet(), hasLength(3));
      for (final path in [
        CommunityConfig.heroImage,
        ...CommunityConfig.communityImages,
      ]) {
        expect(File(path).existsSync(), isTrue, reason: path);
      }
    } else {
      expect(CommunityConfig.heroImage, 'assets/branding/app_icon.png');
      expect(CommunityConfig.communityImages,
          everyElement('assets/branding/app_icon.png'));
    }
  });

  test('el ejemplo es completo y no configura ningún Firebase', () {
    final example = jsonDecode(
      File('config/community.example.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(example['FIREBASE_OPTIONS'], isEmpty);
    expect(example['APP_NAME'], 'MiComunidad');
    expect(jsonDecode(example['COMMUNITY_HISTORY'] as String), hasLength(4));
    final map = jsonDecode(example['COMMUNITY_MAP'] as String) as Map;
    expect(map['landmarks'], hasLength(8));
    expect(map['boundary'], hasLength(25));
  });

  test('los datos del build generan un mapa e historia válidos', () {
    expect(CommunityConfig.history, isNotEmpty);
    expect(CommunityMapData.landmarks, hasLength(8));
    expect(CommunityMapData.communityBoundary, hasLength(25));
    for (final point in CommunityMapData.communityBoundary) {
      expect(point.latitude, inInclusiveRange(-90, 90));
      expect(point.longitude, inInclusiveRange(-180, 180));
    }
  });

  test('sin opciones Firebase no existe conexión predeterminada implícita', () {
    if (!DefaultFirebaseOptions.isConfigured) {
      expect(() => DefaultFirebaseOptions.currentPlatform, throwsStateError);
    } else {
      expect(DefaultFirebaseOptions.currentPlatform.projectId, isNotEmpty);
    }
  });
}
