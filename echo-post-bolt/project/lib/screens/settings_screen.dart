import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Consumer<AppSettingsService>(
        builder: (context, settingsService, child) {
          if (!settingsService.isInitialized) {
            return const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF0055)),
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader('Voice Processing'),
                const SizedBox(height: 16),
                _buildTimeoutSetting(settingsService),
                const SizedBox(height: 32),
                _buildSectionHeader('AI Settings'),
                const SizedBox(height: 16),
                _buildMediaContextSetting(settingsService),
                const SizedBox(height: 16),
                _buildMediaContextLimitSetting(settingsService),
                const SizedBox(height: 32),
                _buildResetButton(settingsService),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildTimeoutSetting(AppSettingsService settingsService) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Voice Transcription Timeout',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'How long to wait for ChatGPT to process your voice command',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: settingsService.voiceTranscriptionTimeout.toDouble(),
                  min: 30,
                  max: 600,
                  divisions: 19, // 30s intervals
                  activeColor: const Color(0xFFFF0055),
                  inactiveColor: Colors.white.withValues(alpha: 0.3),
                  onChanged: (value) async {
                    await settingsService
                        .setVoiceTranscriptionTimeout(value.round());
                  },
                ),
              ),
              Container(
                width: 80,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF0055).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _formatDuration(settingsService.voiceTranscriptionTimeout),
                  style: const TextStyle(
                    color: Color(0xFFFF0055),
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMediaContextSetting(AppSettingsService settingsService) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI Media Context',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Help AI understand your media library for better suggestions',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: settingsService.aiMediaContextEnabled,
            activeColor: const Color(0xFFFF0055),
            onChanged: (value) async {
              await settingsService.setAiMediaContextEnabled(value);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMediaContextLimitSetting(AppSettingsService settingsService) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AI Media Context Limit',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Maximum number of media files to analyze for context',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: settingsService.aiMediaContextLimit.toDouble(),
                  min: 10,
                  max: 500,
                  divisions: 49, // 10-unit intervals
                  activeColor: const Color(0xFFFF0055),
                  inactiveColor: Colors.white.withValues(alpha: 0.3),
                  onChanged: settingsService.aiMediaContextEnabled
                      ? (value) async {
                          await settingsService
                              .setAiMediaContextLimit(value.round());
                        }
                      : null,
                ),
              ),
              Container(
                width: 60,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF0055).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${settingsService.aiMediaContextLimit}',
                  style: const TextStyle(
                    color: Color(0xFFFF0055),
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResetButton(AppSettingsService settingsService) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: Colors.black.withValues(alpha: 0.9),
              title: const Text(
                'Reset Settings',
                style: TextStyle(color: Colors.white),
              ),
              content: const Text(
                'This will reset all settings to their default values. This action cannot be undone.',
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
                  child: const Text(
                    'RESET',
                    style: TextStyle(color: Color(0xFFFF0055)),
                  ),
                ),
              ],
            ),
          );

          if (confirmed == true) {
            await settingsService.resetToDefaults();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Settings reset to defaults'),
                  backgroundColor: Color(0xFFFF0055),
                ),
              );
            }
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.grey.shade800,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Text(
          'Reset to Defaults',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) {
      return '${seconds}s';
    } else {
      final minutes = seconds ~/ 60;
      final remainingSeconds = seconds % 60;
      if (remainingSeconds == 0) {
        return '${minutes}m';
      } else {
        return '${minutes}m ${remainingSeconds}s';
      }
    }
  }
}
