import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'services/media_search_service.dart';
import 'services/social_post_service.dart';
import 'services/ai_service.dart';
import 'services/directory_service.dart';
import 'services/media_metadata_service.dart';
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

  final api_key = dotenv.env['OPENAI_API_KEY'];
  if (api_key == null || api_key.isEmpty) {
    throw Exception('OPENAI_API_KEY not found in .env.local file');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => DirectoryService()),
        ChangeNotifierProvider(create: (_) => MediaMetadataService()),
        Provider<AIService>(
          create: (context) => AIService(
            api_key,
            context.read<MediaMetadataService>(),
          ),
        ),
        Provider<FirestoreService>(
          create: (_) => FirestoreService(),
        ),
        Provider(create: (_) => SocialPostService()),
        Provider(create: (_) => MediaSearchService()),
      ],
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
  );
}
