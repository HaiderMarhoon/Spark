import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'welcome_screen.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import 'otp_screen.dart';
import 'home_screen.dart';
import 'splash_screen.dart'; // Still imported, but not the initial route
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
    // Potentially, you might want to check auth state here
    // and decide the initial route based on that.
    // For now, we are going directly to '/home'.
    // String initialRoute = Provider.of<AuthService>(context, listen: false).isLoggedIn ? '/home' : '/welcome';
    // Forcing /home as per request, but keeping splash for now.
    // If you truly want to bypass any auth check or splash logic,
    // you would set initialRoute directly to '/home'.
    // However, your HomeScreen might expect a logged-in user.

    return MaterialApp(
      title: 'SPARK App',
      debugShowCheckedModeBanner: false,
      theme: _buildAppTheme(),
      // Updated initialRoute to go directly to home.
      // SplashScreen is still a defined route but not the first one.
      initialRoute: '/home', // MODIFIED: Changed from '/splash'
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
      // SplashScreen is still available if navigated to explicitly
      '/splash': (context) => SplashScreen(),
      '/welcome': (context) => const WelcomeScreen(),
      '/login': (context) => const LoginScreen(),
      '/register': (context) => const RegisterScreen(),
      '/otp': (context) {
        // OTP screen might need valid arguments if directly navigated to.
        // Consider how it's used if it's not part of a flow.
        final args = ModalRoute.of(context)!.settings.arguments as Map?;
        return OTPScreen(
          userEmail: args?['userEmail'] ?? '', // Provide default or handle null
          userId: args?['userId'] ?? '', // Provide default or handle null
        );
      },
      // HomeScreen is now the initial route.
      // Note: It's instantiated with empty userId and userEmail here.
      // If HomeScreen requires valid user data from AuthService upon direct load,
      // you might need to adjust how initialRoute is determined or how HomeScreen fetches/receives this data.
      '/home': (context) => const HomeScreen(userId: '', userEmail: ''),
    };
  }
}
