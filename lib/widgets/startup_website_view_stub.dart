import 'package:flutter/material.dart';

class StartupWebsiteView extends StatelessWidget {
  const StartupWebsiteView({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.white,
      child: Center(
        child: Text(
          'This startup website preview is available in Flutter web.',
          style: TextStyle(fontSize: 16, color: Colors.black87),
        ),
      ),
    );
  }
}
