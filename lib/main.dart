import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pages/login_page.dart';
import 'screens/account_settings_screen.dart';
import 'widgets/app_scale_metrics.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Supabase.initialize(
      url: 'https://xljsafhmsncothpsbfpp.supabase.co',
      anonKey: 'sb_publishable_rA1TCLO0cW6h6y69DCdPjw_GWmr0R-r',
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  } catch (e) {
    print('Error initializing Supabase: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Landman Website',
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        return AppScaleWrapper(
          baseWidth: 1440,
          baseHeight: 1024,
          child: child,
        );
      },
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Inter',
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

class AppScaleWrapper extends StatelessWidget {
  const AppScaleWrapper({
    super.key,
    required this.child,
    required this.baseWidth,
    required this.baseHeight,
  });

  final Widget child;
  final double baseWidth;
  final double baseHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaQuery = MediaQuery.of(context);
        final availableWidth = constraints.maxWidth;
        final availableHeight = constraints.maxHeight;

        if (!availableWidth.isFinite || !availableHeight.isFinite) {
          return child;
        }

        final widthRatio = availableWidth / baseWidth;
        final heightRatio = availableHeight / baseHeight;
        // Keep 1340..1440 width filled edge-to-edge by prioritizing width scale.
        final useWidthPriorityScale =
            availableWidth >= 1340 && availableWidth <= baseWidth;
        final rawScale = useWidthPriorityScale
            ? widthRatio
            : math.min(widthRatio, heightRatio);
        final scale = rawScale.clamp(0.0, 1.0);
        final shouldStretchHorizontally = availableWidth > baseWidth;

        final designViewportWidthRaw =
            scale > 0 ? availableWidth / scale : baseWidth;
        final designViewportWidth =
            shouldStretchHorizontally ? designViewportWidthRaw : baseWidth;
        final designCanvasSize = Size(designViewportWidth, baseHeight);

        return SizedBox(
          width: availableWidth,
          height: availableHeight,
          child: ClipRect(
            child: FittedBox(
              fit: useWidthPriorityScale ? BoxFit.fitWidth : BoxFit.contain,
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: designCanvasSize.width,
                height: baseHeight,
                child: AppScaleMetrics(
                  designViewportWidth: designViewportWidth,
                  child: MediaQuery(
                    // Below 1440 keep fixed-width scaling; above 1440 allow horizontal stretch.
                    data: mediaQuery.copyWith(
                      size: designCanvasSize,
                      textScaler: const TextScaler.linear(1.0),
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isInitialized = false;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkAuthState();
    _listenToAuthStateChanges();
  }

  void _checkAuthState() {
    // Check if user is already logged in
    final session = Supabase.instance.client.auth.currentSession;
    setState(() {
      _isInitialized = true;
      _isLoggedIn = session != null;
    });
  }

  void _listenToAuthStateChanges() {
    // Listen for auth state changes
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      final Session? session = data.session;

      setState(() {
        if (event == AuthChangeEvent.signedIn && session != null) {
          _isLoggedIn = true;
        } else if (event == AuthChangeEvent.signedOut) {
          _isLoggedIn = false;
        }
      });
    }, onError: (error) {
      print('Auth state change error: $error');
      // Don't show error for code verifier issues on initial load
      if (error.toString().contains('Code verifier')) {
        print('PKCE code verifier issue, this is expected on page reload');
        // Keep the current auth state
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      // Show loading screen while checking auth state
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0C8CE9)),
          ),
        ),
      );
    }

    if (_isLoggedIn) {
      // User is logged in, show main app
      return AccountSettingsScreen();
    } else {
      // User is not logged in, show login page
      return const LoginPage();
    }
  }
}
