import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'services/social_post_service.dart';
import 'services/ai_service.dart';
import 'services/media_coordinator.dart';
import 'screens/login_screen.dart';
import 'screens/command_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables from .env.local
  await dotenv.load(fileName: ".env.local");

  // Try to initialize Firebase - if it fails, continue without it
  try {
    await Firebase.initializeApp();
    if (kDebugMode) {
      print('Firebase initialized successfully');
    }
  } catch (e) {
    if (kDebugMode) {
      print('Firebase initialization failed: $e');
      print('Continuing without Firebase...');
    }
  }

  final apiKey = dotenv.env['OPENAI_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    throw Exception('OPENAI_API_KEY not found in .env.local file');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider<MediaCoordinator>(
          create: (_) => MediaCoordinator(),
        ),
        Provider<AIService>(
          create: (context) => AIService(apiKey),
        ),
        Provider<FirestoreService>(
          create: (_) => FirestoreService(),
        ),
        Provider<SocialPostService>(
          create: (_) => SocialPostService(),
        ),
      ],
      child: ServiceInitializationWrapper(
        child: MaterialApp(
          title: 'EchoPost',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepPurple,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
            fontFamily: 'Roboto',
            appBarTheme: const AppBarTheme(
              centerTitle: true,
              elevation: 0,
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepPurple,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
            fontFamily: 'Roboto',
            appBarTheme: const AppBarTheme(
              centerTitle: true,
              elevation: 0,
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          themeMode: ThemeMode.system,
          home: Consumer<AuthService>(
            builder: (context, authService, _) {
              return authService.currentUser != null
                  ? const CommandScreen()
                  : const LoginScreen();
            },
          ),
        ),
      ),
    ),
  );
}

/// Wrapper widget that ensures all services are properly initialized
class ServiceInitializationWrapper extends StatefulWidget {
  final Widget child;

  const ServiceInitializationWrapper({
    super.key,
    required this.child,
  });

  @override
  State<ServiceInitializationWrapper> createState() =>
      _ServiceInitializationWrapperState();
}

class _ServiceInitializationWrapperState
    extends State<ServiceInitializationWrapper> {
  bool _isInitialized = false;
  String _initializationStatus = 'Initializing services...';

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      if (kDebugMode) {
        print('🚀 Starting service initialization...');
      }

      setState(() {
        _initializationStatus = 'Initializing media services...';
      });

      // Wait a bit to ensure all providers are ready
      await Future.delayed(const Duration(milliseconds: 100));

      // Initialize all media services through the MediaCoordinator
      final mediaCoordinator =
          Provider.of<MediaCoordinator>(context, listen: false);

      // Check if the coordinator is still valid before initializing
      if (!mounted) {
        if (kDebugMode) {
          print('⚠️ Widget unmounted during initialization, aborting...');
        }
        return;
      }

      await mediaCoordinator.initialize();

      if (kDebugMode) {
        print('✅ MediaCoordinator and all dependent services initialized');
      }

      // Connect AIService with MediaCoordinator
      if (!mounted) return;

      setState(() {
        _initializationStatus = 'Connecting AI service...';
      });

      final aiService = Provider.of<AIService>(context, listen: false);
      aiService.setMediaCoordinator(mediaCoordinator);

      if (kDebugMode) {
        print('🤖 AIService connected to MediaCoordinator');
      }

      if (!mounted) return;

      setState(() {
        _initializationStatus = 'Finalizing initialization...';
      });

      // Small delay to show completion
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      setState(() {
        _isInitialized = true;
      });

      if (kDebugMode) {
        print('🎉 All services initialized successfully!');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Service initialization failed: $e');
      }

      if (!mounted) return;

      setState(() {
        _initializationStatus = 'Initialization failed: $e';
      });

      // Show error but still continue to app
      await Future.delayed(const Duration(seconds: 2));

      if (!mounted) return;

      setState(() {
        _isInitialized = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return MaterialApp(
        title: 'EchoPost',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        home: Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black,
                  Color(0xFF1A1A1A),
                ],
              ),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // App logo/icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF0080),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.mic,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // App name
                  const Text(
                    'EchoPost',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Loading indicator
                  const CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Color(0xFFFF0080)),
                  ),
                  const SizedBox(height: 24),

                  // Status text
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      _initializationStatus,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return widget.child;
  }
}
