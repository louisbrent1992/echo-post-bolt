import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';

import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/media_coordinator.dart';
import '../services/social_action_post_coordinator.dart';
import '../screens/history_screen.dart';
import '../widgets/social_icon.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _userData;
  bool _directoryPermissionGranted = false;
  bool _microphonePermissionGranted = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _checkPermissions();
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

  Future<void> _checkPermissions() async {
    try {
      // Check directory permissions using PhotoManager (same as Command Screen)
      final directoryPermissionState =
          await PhotoManager.requestPermissionExtend();
      final directoryGranted = directoryPermissionState.hasAccess;

      // Check microphone permission (same as Command Screen)
      final microphoneGranted = await Permission.microphone.status.isGranted;

      setState(() {
        _directoryPermissionGranted = directoryGranted;
        _microphonePermissionGranted = microphoneGranted;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking permissions: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _requestDirectoryPermission() async {
    try {
      // Request directory permissions using PhotoManager (same as Command Screen)
      final permissionState = await PhotoManager.requestPermissionExtend();
      final granted = permissionState.hasAccess;

      setState(() {
        _directoryPermissionGranted = granted;
      });

      if (granted && mounted) {
        // Refresh media coordinator after permission granted (same as Command Screen)
        final mediaCoordinator =
            Provider.of<MediaCoordinator>(context, listen: false);
        await mediaCoordinator.initialize();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Directory access granted! You can now select photos and videos.'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Directory access is required to select media files.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error requesting directory permission: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _requestMicrophonePermission() async {
    try {
      // Request microphone permission (same as Command Screen)
      final status = await Permission.microphone.request();
      final granted = status.isGranted;

      setState(() {
        _microphonePermissionGranted = granted;
      });

      if (granted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Microphone access granted! You can now record voice commands.'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone access is required for voice recording.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error requesting microphone permission: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _logout() async {
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
        final authService = Provider.of<AuthService>(context, listen: false);
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

                  // Permissions Section
                  const Row(
                    children: [
                      Icon(
                        Icons.security,
                        color: Color(0xFFFF0055),
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Permissions',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Directory Permission Toggle
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: _directoryPermissionGranted
                          ? const Color(0xFFFF0055).withValues(alpha: 0.1)
                          : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _directoryPermissionGranted
                            ? const Color(0xFFFF0055).withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: SwitchListTile(
                      value: _directoryPermissionGranted,
                      onChanged: _directoryPermissionGranted
                          ? null
                          : (value) => _requestDirectoryPermission(),
                      title: const Text(
                        'Directory Access',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        _directoryPermissionGranted
                            ? 'Access to photos and videos granted'
                            : 'Allow access to select photos and videos',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                      activeColor: const Color(0xFFFF0055),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),

                  // Microphone Permission Toggle
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: _microphonePermissionGranted
                          ? const Color(0xFFFF0055).withValues(alpha: 0.1)
                          : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _microphonePermissionGranted
                            ? const Color(0xFFFF0055).withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: SwitchListTile(
                      value: _microphonePermissionGranted,
                      onChanged: _microphonePermissionGranted
                          ? null
                          : (value) => _requestMicrophonePermission(),
                      title: const Text(
                        'Microphone Access',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        _microphonePermissionGranted
                            ? 'Microphone access granted'
                            : 'Allow access for voice recording',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                      activeColor: const Color(0xFFFF0055),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                  const SizedBox(height: 24),

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
