import 'dart:convert';

/// Build-time configuration. Never put server credentials here.
class CommunityConfig {
  CommunityConfig._();
  // Asset inclusion follows the same Flutter flavor as the Android build.
  static const usesPrivateImages =
      String.fromEnvironment('FLUTTER_APP_FLAVOR') == 'private';
  static const heroImage = usesPrivateImages
      ? 'assets/images/Imagen_de_Inicio.png'
      : 'assets/branding/app_icon.png';
  static const communityImages = usesPrivateImages
      ? [
          'assets/images/community/community_view.png',
          'assets/images/community/community_families.png',
          'assets/images/community/community_work.png',
        ]
      : [
          'assets/branding/app_icon.png',
          'assets/branding/app_icon.png',
          'assets/branding/app_icon.png',
        ];
  static const legalName = String.fromEnvironment('COMMUNITY_LEGAL_NAME',
      defaultValue: 'MiComunidad');
  static const anniversaryTitle = String.fromEnvironment('ANNIVERSARY_TITLE',
      defaultValue: 'Participación comunitaria');
  static const anniversaryDates = String.fromEnvironment('ANNIVERSARY_DATES',
      defaultValue: 'Contenido de demostración');
  static final history = List<String>.unmodifiable((jsonDecode(const String
              .fromEnvironment('COMMUNITY_HISTORY',
              defaultValue:
                  '["MiComunidad facilita la organización y participación vecinal.","Esta historia es ficticia y no describe una comunidad real.","Los lugares, las cifras y las imágenes de esta edición son demostrativos.","Configura tus propios datos únicamente en una instalación privada."]'))
          as List)
      .cast<String>());
  static final Map<String, dynamic> map = jsonDecode(const String
          .fromEnvironment('COMMUNITY_MAP',
          defaultValue:
              '{"reference":[0.001,-30.001],"center":[0,-30],"bounds":[[-0.005,-30.005],[0.005,-29.995]],"url":"https://www.google.com/maps/search/?api=1&query=0,-30","landmarks":[{"name":"Punto demo 1","description":"Referencia ficticia, no corresponde a residentes reales.","point":[-0.001,-30.001],"icon":"transport"},{"name":"Punto demo 2","description":"Referencia ficticia, no corresponde a residentes reales.","point":[0,-30.001],"icon":"religion"},{"name":"Punto demo 3","description":"Referencia ficticia, no corresponde a residentes reales.","point":[0.001,-30.001],"icon":"community"},{"name":"Punto demo 4","description":"Referencia ficticia, no corresponde a residentes reales.","point":[-0.001,-30],"icon":"community"},{"name":"Punto demo 5","description":"Referencia ficticia, no corresponde a residentes reales.","point":[0,-30],"icon":"shop"},{"name":"Punto demo 6","description":"Referencia ficticia, no corresponde a residentes reales.","point":[0.001,-30],"icon":"religion"},{"name":"Punto demo 7","description":"Referencia ficticia, no corresponde a residentes reales.","point":[-0.001,-29.999],"icon":"sports"},{"name":"Punto demo 8","description":"Referencia ficticia, no corresponde a residentes reales.","point":[0,-29.999],"icon":"bank"}],"boundary":[[0,-29.997],[0.0007460696614945644,-29.997094250516614],[0.001445261022305146,-29.99737107995987],[0.002053641317786066,-29.997813094117735],[0.002532983776506045,-29.998392519615063],[0.0028531695488854605,-29.999072949016874],[0.002994080185284815,-29.999811628441414],[0.0029468617521860663,-30.000562143943757],[0.0027144811573980585,-30.001277337874694],[0.0023115397283273676,-30.001912271969246],[0.0017633557568774198,-30.002427050983126],[0.0011043736580540345,-30.002789329457666],[0.0003759997006929136,-30.002976344103942],[-0.0003759997006929129,-30.002976344103942],[-0.0011043736580540339,-30.002789329457666],[-0.001763355756877418,-30.002427050983126],[-0.002311539728327368,-30.001912271969246],[-0.0027144811573980594,-30.001277337874694],[-0.0029468617521860663,-30.000562143943757],[-0.002994080185284815,-29.999811628441414],[-0.002853169548885461,-29.999072949016874],[-0.0025329837765060447,-29.998392519615063],[-0.0020536413177860667,-29.997813094117735],[-0.0014452610223051484,-29.99737107995987],[-0.0007460696614945661,-29.997094250516614]]}'))
      as Map<String, dynamic>;
}
