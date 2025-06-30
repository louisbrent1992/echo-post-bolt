import 'package:flutter/material.dart';

class TermsPrivacyScreen extends StatelessWidget {
  const TermsPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms & Privacy'),
        backgroundColor: const Color(0xFF2A2A2A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Terms of Service',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'By using EchoPost, you agree to these terms:',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              _buildSection(
                '1. Service Description',
                'EchoPost is a voice-driven social media posting application that helps you create and manage content across multiple social media platforms.',
              ),
              _buildSection(
                '2. User Responsibilities',
                'You are responsible for all content you post through EchoPost. You must not post illegal, harmful, or inappropriate content.',
              ),
              _buildSection(
                '3. Privacy & Data',
                'We collect and process your data as described in our Privacy Policy below. Your data is used to provide and improve our services.',
              ),
              _buildSection(
                '4. Account Security',
                'You are responsible for maintaining the security of your account credentials and for all activities that occur under your account.',
              ),
              _buildSection(
                '5. Service Availability',
                'We strive to provide reliable service but cannot guarantee uninterrupted availability. We may update or modify the service at any time.',
              ),
              _buildSection(
                '6. Termination',
                'We may terminate or suspend your account at any time for violations of these terms or for any other reason at our discretion.',
              ),
              const SizedBox(height: 32),
              const Text(
                'Privacy Policy',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Your privacy is important to us. Here\'s how we handle your data:',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              _buildSection(
                'Data We Collect',
                '• Account information (email, name, profile picture)\n• Social media platform connections and tokens\n• Voice recordings and transcriptions\n• Usage data and app interactions\n• Device information and app performance data',
              ),
              _buildSection(
                'How We Use Your Data',
                '• To provide and improve our services\n• To authenticate your identity\n• To post content to your connected social media accounts\n• To personalize your experience\n• To communicate with you about our services',
              ),
              _buildSection(
                'Data Sharing',
                'We do not sell your personal data. We may share data with:\n• Social media platforms (when you authorize connections)\n• Service providers who help us operate the app\n• Legal authorities when required by law',
              ),
              _buildSection(
                'Data Security',
                'We implement appropriate security measures to protect your data. However, no method of transmission over the internet is 100% secure.',
              ),
              _buildSection(
                'Your Rights',
                'You have the right to:\n• Access your personal data\n• Correct inaccurate data\n• Delete your account and data\n• Opt out of certain data processing\n• Export your data',
              ),
              _buildSection(
                'Data Retention',
                'We retain your data as long as your account is active or as needed to provide services. You can request deletion of your data at any time.',
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF0055).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFFF0055).withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: const Color(0xFFFF0055),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Contact Us',
                          style: TextStyle(
                            color: Color(0xFFFF0055),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'If you have questions about these terms or our privacy practices, please contact us at support@echopost.app',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Last updated: ${DateTime.now().year}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
