class AppIdentity {
  const AppIdentity._();
  static const appName =
      String.fromEnvironment('APP_NAME', defaultValue: 'MiComunidad');
  static const communityName =
      String.fromEnvironment('COMMUNITY_NAME', defaultValue: 'MiComunidad');
  static const shortName =
      String.fromEnvironment('SHORT_NAME', defaultValue: 'MiComunidad');
}
