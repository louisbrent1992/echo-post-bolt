// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:echo_post/main.dart';
import 'package:echo_post/services/account_auth_service.dart';
import 'package:echo_post/services/media_coordinator.dart';
import 'package:echo_post/services/firestore_service.dart';
import 'package:echo_post/services/ai_service.dart';
import 'package:echo_post/services/social_post_service.dart';
import 'package:echo_post/services/natural_language_parser.dart';
import 'package:echo_post/services/social_action_post_coordinator.dart';
import 'package:echo_post/services/app_settings_service.dart';
import 'package:echo_post/services/permission_manager.dart';
import 'package:echo_post/screens/command_screen.dart';
import 'package:echo_post/screens/login_screen.dart';

void main() {
  testWidgets('EchoPost app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AccountAuthService()),
          ChangeNotifierProvider(create: (_) => AppSettingsService()),
          ChangeNotifierProvider<MediaCoordinator>(
            create: (_) => MediaCoordinator(),
          ),
          Provider<AIService>(
            create: (context) => AIService(
              'test-api-key',
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
            create: (context) => SocialActionPostCoordinator(
              mediaCoordinator: context.read<MediaCoordinator>(),
              firestoreService: context.read<FirestoreService>(),
              aiService: context.read<AIService>(),
              socialPostService: context.read<SocialPostService>(),
              authService: context.read<AccountAuthService>(),
              naturalLanguageParser: context.read<NaturalLanguageParser>(),
            ),
          ),
          ChangeNotifierProvider<PermissionManager>(
            create: (_) => PermissionManager(),
          ),
        ],
        child: ServiceInitializationWrapper(
          child: Builder(
            builder: (context) {
              return MaterialApp(
                title: 'EchoPost',
                theme: ThemeData(
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: Colors.deepPurple,
                    brightness: Brightness.light,
                  ),
                  useMaterial3: true,
                ),
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

    // Verify that the app loads without crashing
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
