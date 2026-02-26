import 'dart:html' as html;

import 'package:flutter/material.dart';

class StartupWebsiteView extends StatefulWidget {
  const StartupWebsiteView({super.key});

  @override
  State<StartupWebsiteView> createState() => _StartupWebsiteViewState();
}

class _StartupWebsiteViewState extends State<StartupWebsiteView> {
  static const String _startupUrl = '/website_8answers%20copy%202/index.html';
  bool _hasRedirected = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _redirectIfNeeded();
  }

  void _redirectIfNeeded() {
    if (_hasRedirected) return;
    _hasRedirected = true;

    final currentPath = html.window.location.pathname ?? '';
    if (currentPath.contains('/website_8answers%20copy%202/') ||
        currentPath.contains('/website_8answers copy 2/')) {
      return;
    }

    html.window.location.replace(_startupUrl);
  }

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.white,
      child: Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0C8CE9)),
        ),
      ),
    );
  }
}
