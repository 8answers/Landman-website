import 'dart:html' as html;

Future<bool> isReloadNavigation() async {
  try {
    final performance = html.window.performance;

    // Legacy API still available in browsers used by Flutter web.
    final legacyNavigation = performance.navigation;
    return legacyNavigation.type == 1;
  } catch (_) {
    // If navigation type can't be determined, treat as fresh open.
  }

  return false;
}
