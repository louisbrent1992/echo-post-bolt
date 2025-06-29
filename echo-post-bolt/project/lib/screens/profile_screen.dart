import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../services/account_auth_service.dart';
import '../services/auth/facebook_auth_service.dart';
import '../services/auth/instagram_auth_service.dart';
import '../services/auth/youtube_auth_service.dart';
import '../services/auth/twitter_auth_service.dart';
import '../services/auth/tiktok_auth_service.dart';
import '../screens/history_screen.dart';
import '../constants/social_platforms.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _userData;
  Map<String, bool> _platformConnections = {};
  bool _disconnectingAll = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadPlatformConnections();
  }

  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          setState(() {
            _userData = userDoc.data();
            _isLoading = false;
          });
        } else {
          setState(() {
            _userData = {
              'displayName': user.displayName ?? 'User',
              'email': user.email ?? 'No email',
              'photoURL': user.photoURL,
              'provider': 'unknown',
            };
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadPlatformConnections() async {
    final authService = Provider.of<AccountAuthService>(context, listen: false);
    final Map<String, bool> connections = {};
    for (final platform in SocialPlatforms.all) {
      connections[platform] = await authService.isPlatformConnected(platform);
    }
    if (mounted) {
      setState(() {
        _platformConnections = connections;
      });
    }
  }

  Future<void> _disconnectPlatform(String platform) async {
    try {
      if (kDebugMode) {
        print('🔌 Disconnecting from $platform...');
      }

      // Use the appropriate service to properly sign out from each platform
      switch (platform.toLowerCase()) {
        case 'facebook':
          final facebookAuth = FacebookAuthService();
          await facebookAuth.signOutOfFacebook();
          break;
        case 'instagram':
          final instagramAuth = InstagramAuthService();
          await instagramAuth.signOutOfInstagram();
          break;
        case 'youtube':
          final youtubeAuth = YouTubeAuthService();
          await youtubeAuth.signOutOfYouTube();
          break;
        case 'twitter':
          final twitterAuth = TwitterAuthService();
          await twitterAuth.signOutOfTwitter();
          break;
        case 'tiktok':
          final tiktokAuth = TikTokAuthService();
          await tiktokAuth.signOutOfTikTok();
          break;
        default:
          // Fallback to the old method for unknown platforms
          final authService =
              Provider.of<AccountAuthService>(context, listen: false);
          await authService.disconnectPlatform(platform);
      }

      await _loadPlatformConnections();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Disconnected from ${SocialPlatforms.getDisplayName(platform)} ✅'),
            backgroundColor: Colors.green.withValues(alpha: 0.8),
          ),
        );
      }

      if (kDebugMode) {
        print('✅ Successfully disconnected from $platform');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to disconnect from $platform: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Failed to disconnect from ${SocialPlatforms.getDisplayName(platform)}: $e'),
            backgroundColor: Colors.red.withValues(alpha: 0.8),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _disconnectAllPlatforms() async {
    setState(() => _disconnectingAll = true);

    try {
      if (kDebugMode) {
        print('🔌 Disconnecting from all platforms...');
      }

      int successCount = 0;
      int totalCount = 0;

      for (final platform in SocialPlatforms.all) {
        if (_platformConnections[platform] == true) {
          totalCount++;
          try {
            await _disconnectPlatformSilently(platform);
            successCount++;
          } catch (e) {
            if (kDebugMode) {
              print('❌ Failed to disconnect from $platform: $e');
            }
          }
        }
      }

      await _loadPlatformConnections();

      if (mounted) {
        if (successCount == totalCount && totalCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Disconnected from all platforms ✅ ($successCount/$totalCount)'),
              backgroundColor: Colors.green.withValues(alpha: 0.8),
            ),
          );
        } else if (successCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Partially disconnected ($successCount/$totalCount platforms)'),
              backgroundColor: Colors.orange.withValues(alpha: 0.8),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Failed to disconnect platforms'),
              backgroundColor: Colors.red.withValues(alpha: 0.8),
            ),
          );
        }
      }

      if (kDebugMode) {
        print(
            '✅ Disconnect all completed: $successCount/$totalCount platforms');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error during disconnect all: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to disconnect all platforms: $e'),
            backgroundColor: Colors.red.withValues(alpha: 0.8),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _disconnectingAll = false);
    }
  }

  /// Helper method to disconnect a platform without showing individual success/error messages
  Future<void> _disconnectPlatformSilently(String platform) async {
    switch (platform.toLowerCase()) {
      case 'facebook':
        final facebookAuth = FacebookAuthService();
        await facebookAuth.signOutOfFacebook();
        break;
      case 'instagram':
        final instagramAuth = InstagramAuthService();
        await instagramAuth.signOutOfInstagram();
        break;
      case 'youtube':
        final youtubeAuth = YouTubeAuthService();
        await youtubeAuth.signOutOfYouTube();
        break;
      case 'twitter':
        final twitterAuth = TwitterAuthService();
        await twitterAuth.signOutOfTwitter();
        break;
      case 'tiktok':
        final tiktokAuth = TikTokAuthService();
        await tiktokAuth.signOutOfTikTok();
        break;
      default:
        // Fallback to the old method for unknown platforms
        final authService =
            Provider.of<AccountAuthService>(context, listen: false);
        await authService.disconnectPlatform(platform);
    }
  }

  Future<void> _logout() async {
    // Capture AuthService before any async operations
    final authService = Provider.of<AccountAuthService>(context, listen: false);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          'Sign Out?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to sign out of your account?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF0055),
            ),
            child: const Text('SIGN OUT'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await authService.signOut();

        if (mounted) {
          // Navigate back to login screen - handled by auth state listener in main.dart
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to sign out: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _navigateToHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const HistoryScreen(),
      ),
    );
  }

  String _getAuthMethodDisplayName(String? provider) {
    switch (provider) {
      case 'google.com':
        return 'Google Sign-In';
      case 'password':
        return 'Email & Password';
      case 'facebook.com':
        return 'Facebook';
      default:
        return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF0055)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Profile Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFFF0055).withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        // Profile Image
                        CircleAvatar(
                          radius: 50,
                          backgroundColor:
                              const Color(0xFFFF0055).withValues(alpha: 0.2),
                          backgroundImage: user?.photoURL != null
                              ? NetworkImage(user!.photoURL!)
                              : null,
                          child: user?.photoURL == null
                              ? const Icon(
                                  Icons.person,
                                  size: 50,
                                  color: Color(0xFFFF0055),
                                )
                              : null,
                        ),
                        const SizedBox(height: 16),

                        // Name
                        Text(
                          _userData?['displayName'] ??
                              user?.displayName ??
                              'User',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Email
                        Text(
                          _userData?['email'] ?? user?.email ?? 'No email',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Auth Method
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFFFF0055).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFFF0055)
                                  .withValues(alpha: 0.5),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            _getAuthMethodDisplayName(_userData?['provider']),
                            style: const TextStyle(
                              color: Color(0xFFFF0055),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Navigation Section
                  const Row(
                    children: [
                      Icon(
                        Icons.navigation,
                        color: Color(0xFFFF0055),
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Navigation',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Post History Button
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFFF0055).withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: ListTile(
                      leading: const Icon(
                        Icons.history,
                        color: Color(0xFFFF0055),
                      ),
                      title: const Text(
                        'Post History',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: const Text(
                        'View your published posts',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white54,
                        size: 16,
                      ),
                      onTap: _navigateToHistory,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Manage Connected Accounts Section
                  const SizedBox(height: 24),
                  const Row(
                    children: [
                      Icon(Icons.link, color: Color(0xFFFF0055), size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Manage Connected Accounts',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFFF0055).withValues(alpha: 0.2),
                        width: 1.2,
                      ),
                    ),
                    child: Column(
                      children: [
                        for (final platform in SocialPlatforms.all)
                          ListTile(
                            leading: Icon(
                              SocialPlatforms.getIcon(platform),
                              color: _platformConnections[platform] == true
                                  ? const Color(0xFFFF0055)
                                  : Colors.white.withValues(alpha: 0.4),
                            ),
                            title: Text(
                              SocialPlatforms.getDisplayName(platform),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              _platformConnections[platform] == true
                                  ? 'Connected'
                                  : 'Not Connected',
                              style: TextStyle(
                                color: _platformConnections[platform] == true
                                    ? Colors.greenAccent
                                    : Colors.white.withValues(alpha: 0.5),
                                fontSize: 12,
                              ),
                            ),
                            trailing: _platformConnections[platform] == true
                                ? TextButton(
                                    onPressed: () =>
                                        _disconnectPlatform(platform),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.red,
                                    ),
                                    child: const Text('Disconnect'),
                                  )
                                : null,
                          ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _disconnectingAll
                              ? null
                              : _disconnectAllPlatforms,
                          icon: const Icon(Icons.link_off),
                          label: const Text('Disconnect All'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Account Actions Section
                  const Row(
                    children: [
                      Icon(
                        Icons.settings,
                        color: Color(0xFFFF0055),
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Account',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Logout Button
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFFF0055).withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: ListTile(
                      leading: const Icon(
                        Icons.logout,
                        color: Colors.red,
                      ),
                      title: const Text(
                        'Sign Out',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: const Text(
                        'Sign out of your account',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      onTap: _logout,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
