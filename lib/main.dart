import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'welcome_screen.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import 'homes.dart';
import 'homes_rig.dart';
import 'otp_screen.dart';
import 'home_screen.dart';
import 'splash_screen.dart';
import 'auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with platform-specific options
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize authentication service
  final authService = AuthService(FirebaseAuth.instance);

  runApp(
    ChangeNotifierProvider(
      create: (context) => authService,
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SPARK App',
      debugShowCheckedModeBanner: false,
      theme: _buildAppTheme(),
      // --- MODIFIED: Change initialRoute to '/home' to skip auth for testing ---
      // Original: initialRoute: '/splash',
      initialRoute: '/home',
      // ----------------------------------------------------------------------
      routes: _buildAppRoutes(),
      navigatorObservers: [RouteObserver<PageRoute>()],
    );
  }

  ThemeData _buildAppTheme() {
    return ThemeData(
      primarySwatch: Colors.green,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF41E181),
        brightness: Brightness.light,
        secondary: Colors.blueAccent,
      ),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Map<String, WidgetBuilder> _buildAppRoutes() {
    return {
      '/splash': (context) => SplashScreen(),
      '/welcome': (context) => const WelcomeScreen(),
      '/login': (context) => const LoginScreen(),
      '/register': (context) => const RegisterScreen(),
      '/homes': (context) => const HomesPage(),
      '/homes_rig': (context) => const HomeRegistrationPage(),
      '/otp': (context) {
        // Note: This route might not work correctly without proper arguments
        // if accessed directly without the phone verification flow.
        final args = ModalRoute.of(context)!.settings.arguments as Map;
        return OTPScreen(
          userEmail: '', // Placeholder
          userId: '', // Placeholder
        );
      },
      // --- MODIFIED: Provide placeholder arguments for the /home route when skipping auth ---
      // Original: '/home': (context) => const HomeScreen(userId: '', userEmail: '',),
      '/home': (context) => const HomeScreen(userId: 'placeholder_user_id', userEmail: 'placeholder@example.com'),
      // ------------------------------------------------------------------------------------
    };
  }
}
