import 'package:shared_preferences/shared_preferences.dart';

class AreaUnitService {
  static const String _prefix = 'project_';
  static const String _suffix = '_area_unit';
  static const String defaultUnit = 'Square Feet (sqft)';

  static String _key(String? projectId) =>
      '${_prefix}${projectId ?? 'default'}$_suffix';

  static Future<String> getAreaUnit(String? projectId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key(projectId)) ?? defaultUnit;
  }

  static Future<void> setAreaUnit(String? projectId, String unit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(projectId), unit);
  }
}
