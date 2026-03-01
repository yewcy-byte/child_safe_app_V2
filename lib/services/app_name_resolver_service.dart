import 'package:device_apps/device_apps.dart';

class AppNameResolverService {
  static final AppNameResolverService _instance = AppNameResolverService._internal();

  factory AppNameResolverService() => _instance;

  AppNameResolverService._internal();

  static final Map<String, String> _appNameCache = {};

  Future<String> getAppName(String packageName) async {
    if (_appNameCache.containsKey(packageName)) {
      return _appNameCache[packageName]!;
    }

    try {
      final app = await DeviceApps.getApp(packageName);
      if (app != null) {
        final appName = app.appName;
        _appNameCache[packageName] = appName;
        return appName;
      }
    } catch (e) {
      // App not installed or unable to resolve name, will return package name
    }

    _appNameCache[packageName] = packageName;
    return packageName;
  }

  void clearCache() {
    _appNameCache.clear();
  }
}
