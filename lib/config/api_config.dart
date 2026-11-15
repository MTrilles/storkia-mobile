class ApiConfig {
  static const String domainUrl = String.fromEnvironment(
    'STORKIA_DOMAIN',
    defaultValue: 'https://storkia.shop',
  );

  static const String baseUrl = '$domainUrl/api/v1';

  static const String pusherKey = String.fromEnvironment(
    'REVERB_APP_KEY',
    defaultValue: 'bn93mdlba1frvyhfe5gf',
  );

  static const String websocketHost = String.fromEnvironment(
    'STORKIA_WS_HOST',
    defaultValue: 'storkia.shop',
  );

  static const int websocketPort = int.fromEnvironment(
    'REVERB_PORT',
    defaultValue: 8080,
  );

  static const Duration requestTimeout = Duration(seconds: 20);

  static String resolveBaseDomain([String? overrideBaseUrl]) {
    if (overrideBaseUrl == null || overrideBaseUrl.trim().isEmpty) {
      return domainUrl;
    }
    String clean = overrideBaseUrl.trim();
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    if (clean.endsWith('/api/v1')) {
      clean = clean.substring(0, clean.length - 7);
    }
    return clean;
  }

  static String storageUrl(String? path, [String? overrideBaseUrl]) {
    if (path == null || path.trim().isEmpty) return '';
    final cleanPath = path.trim();
    if (cleanPath.startsWith('http://') || cleanPath.startsWith('https://')) {
      return cleanPath;
    }
    final domain = resolveBaseDomain(overrideBaseUrl);
    final normalized =
        cleanPath.startsWith('/') ? cleanPath.substring(1) : cleanPath;
    if (normalized.startsWith('storage/')) {
      return '$domain/$normalized';
    }
    return '$domain/storage/$normalized';
  }
}
