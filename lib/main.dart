import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pages/login_page.dart';
import 'screens/account_settings_screen.dart';

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
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Inter',
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
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