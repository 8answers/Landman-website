import 'dart:html' as html;

Future<bool> redirectToLandingIfNeeded() async {
  final uri = Uri.base;
  final path = uri.path;
  final queryParams = uri.queryParameters;
  final hashValue = html.window.location.hash;
  final hashQuery = hashValue.startsWith('#') ? hashValue.substring(1) : '';
  final hashParams = Uri.splitQueryString(
    hashQuery.contains('=') ? hashQuery : '',
  );
  final hasAuthFlowParams = queryParams.containsKey('code') ||
      queryParams.containsKey('state') ||
      queryParams.containsKey('access_token') ||
      queryParams.containsKey('refresh_token') ||
      queryParams.containsKey('id_token') ||
      queryParams.containsKey('auth') ||
      queryParams.containsKey('invite') ||
      queryParams.containsKey('projectId') ||
      queryParams.containsKey('inv') ||
      queryParams.containsKey('inviteToken') ||
      hashParams.containsKey('access_token') ||
      hashParams.containsKey('refresh_token') ||
      hashParams.containsKey('id_token');
  if (hasAuthFlowParams) return false;

  final isRootPath = path.isEmpty || path == '/' || path == '/index.html';
  if (!isRootPath) return false;

  const target = '/website_8answers%20copy%202/index.html';
  final current = html.window.location.pathname ?? '';
  if (current.contains('/website_8answers%20copy%202/') ||
      current.contains('/website_8answers copy 2/')) {
    return false;
  }

  html.window.location.replace(target);
  return true;
}
