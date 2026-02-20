import 'package:flutter/widgets.dart';

class AppScaleMetrics extends InheritedWidget {
  const AppScaleMetrics({
    super.key,
    required this.designViewportWidth,
    required super.child,
  });

  final double designViewportWidth;

  static AppScaleMetrics? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppScaleMetrics>();
  }

  @override
  bool updateShouldNotify(AppScaleMetrics oldWidget) {
    return oldWidget.designViewportWidth != designViewportWidth;
  }
}
