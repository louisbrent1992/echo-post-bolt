import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'route_observer.dart';
import 'services/account_auth_service.dart';
import 'services/media_coordinator.dart';
import 'services/firestore_service.dart';
import 'services/ai_service.dart';
import 'services/social_post_service.dart';
import 'services/natural_language_parser.dart';
import 'services/social_action_post_coordinator.dart';
import 'services/app_settings_service.dart';
import 'services/permission_manager.dart';
import 'screens/command_screen.dart';
import 'screens/login_screen.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables from .env.local (optional for development)
  try {
    await dotenv.load(fileName: ".env.local");
    if (kDebugMode) {
      print('✅ Environment variables loaded from .env.local');
    }
  } catch (e) {
    if (kDebugMode) {
      print('⚠️ .env.local not found, using development defaults');
      print(
          '   Create .env.local file with your API keys for full functionality');
    }
  }

  // Try to initialize Firebase with proper options
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (kDebugMode) {
      print('✅ Firebase initialized successfully');
    }
  } catch (e) {
    if (kDebugMode) {
      print('⚠️ Firebase initialization failed: $e');
      print('   Continuing without Firebase...');
    }
  }

  // Get API key with fallback for development
  final apiKey = dotenv.env['OPENAI_API_KEY'] ?? 'development_key';
  if (apiKey == 'development_key') {
    if (kDebugMode) {
      print('⚠️ Using development API key - AI features will be limited');
      print('   Set OPENAI_API_KEY in .env.local for full AI functionality');
    }
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AccountAuthService()),
        ChangeNotifierProvider(create: (_) => AppSettingsService()),
        ChangeNotifierProvider<MediaCoordinator>(
          create: (_) => MediaCoordinator(),
        ),
        Provider<AIService>(
          create: (context) => AIService(
            apiKey,
            context.read<MediaCoordinator>(),
          ),
        ),
        Provider<FirestoreService>(
          create: (_) => FirestoreService(),
        ),
        Provider<SocialPostService>(
          create: (_) => SocialPostService(),
        ),
        Provider<NaturalLanguageParser>(
          create: (_) => NaturalLanguageParser(),
        ),
        ChangeNotifierProvider<SocialActionPostCoordinator>(
          create: (context) {
            final coordinator = SocialActionPostCoordinator(
              mediaCoordinator: context.read<MediaCoordinator>(),
              firestoreService: context.read<FirestoreService>(),
              aiService: context.read<AIService>(),
              socialPostService: context.read<SocialPostService>(),
              authService: context.read<AccountAuthService>(),
              naturalLanguageParser: context.read<NaturalLanguageParser>(),
            );

            if (kDebugMode) {
              print(
                  '🔧 SocialActionPostCoordinator created with direct dependencies');
            }

            // Initialize authentication state after coordinator creation
            coordinator.initializeAuthenticationState();

            return coordinator;
          },
          lazy: false,
        ),
        ChangeNotifierProvider<PermissionManager>(
          create: (_) => PermissionManager(),
        ),
      ],
      child: ServiceInitializationWrapper(
        child: Builder(
          builder: (context) {
            // Add error boundary to catch framework errors
            return MaterialApp(
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
              navigatorObservers: [routeObserver],
              home: Consumer<AccountAuthService>(
                builder: (context, authService, _) {
                  return authService.currentUser != null
                      ? const CommandScreen()
                      : const LoginScreen();
                },
              ),
            );
          },
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
        print('🌐 Platform: ${kIsWeb ? 'Web' : 'Mobile'}');
      }

      setState(() {
        _initializationStatus = 'Initializing services...';
      });

      // Capture all providers before any async operations
      final appSettingsService =
          Provider.of<AppSettingsService>(context, listen: false);
      final mediaCoordinator =
          Provider.of<MediaCoordinator>(context, listen: false);

      // Initialize AppSettingsService first
      try {
        await appSettingsService.initialize();
        if (kDebugMode) {
          print('✅ AppSettingsService initialized');
        }
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ AppSettingsService initialization failed: $e');
        }
      }

      // Wait a bit to ensure all providers are ready
      await Future.delayed(const Duration(milliseconds: 50));

      if (!mounted) {
        if (kDebugMode) {
          print('⚠️ Widget unmounted during initialization, aborting...');
        }
        return;
      }

      // Initialize permission manager (skip on web)
      if (!kIsWeb) {
        try {
          final permissionManager = PermissionManager();
          if (kDebugMode) {
            print('🔐 Requesting media permissions...');
          }
          final hasPermissions =
              await permissionManager.requestAllPermissions();

          if (!hasPermissions) {
            if (kDebugMode) {
              print(
                  '⚠️ Permissions not granted, but continuing with limited functionality');
            }
          } else {
            if (kDebugMode) {
              print('✅ All permissions granted successfully');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('⚠️ Permission initialization failed: $e');
          }
        }
      } else {
        if (kDebugMode) {
          print('🌐 Web platform - skipping permission requests');
        }
      }

      // Initialize media coordinator
      try {
        if (kDebugMode) {
          print('🎛️ Initializing MediaCoordinator...');
        }
        await mediaCoordinator.initialize();
        if (kDebugMode) {
          print('✅ MediaCoordinator initialized');
        }
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ MediaCoordinator initialization failed: $e');
        }
      }

      if (kDebugMode) {
        print('✅ Service initialization completed');
      }

      if (!mounted) return;

      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      if (kDebugMode) {
        print('❌ Service initialization failed: $e');
      }

      if (!mounted) return;

      // Even if initialization fails, show the app
      setState(() {
        _isInitialized = true;
        _initializationStatus = 'Initialization completed with warnings';
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
                stops: [0.0, 0.3, 0.7, 1.0],
                colors: [
                  Color(0xFF000000), // Pure black at top
                  Color(0xFF1A1A1A), // Dark gray
                  Color(0xFF2A2A2A), // Medium dark gray
                  Color(0xFF1A1A1A), // Back to dark gray at bottom
                ],
              ),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // App logo/icon
                  Image.asset(
                    'assets/icons/logo.png',
                    width: 80,
                    height: 80,
                    fit: BoxFit.contain,
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
                        AlwaysStoppedAnimation<Color>(Color(0xFFFF0055)),
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
