import 'dart:html' as html;

bool openMailTo(String email) {
  final trimmed = email.trim();
  if (trimmed.isEmpty) return false;
  html.window.open('mailto:$trimmed', '_self');
  return true;
}
