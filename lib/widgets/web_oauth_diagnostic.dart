import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/auth/web_oauth_status.dart';

/// Diagnostic widget for web OAuth configuration
class WebOAuthDiagnostic extends StatefulWidget {
  const WebOAuthDiagnostic({super.key});

  @override
  State<WebOAuthDiagnostic> createState() => _WebOAuthDiagnosticState();
}

class _WebOAuthDiagnosticState extends State<WebOAuthDiagnostic> {
  Map<String, dynamic>? _status;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    setState(() => _isLoading = true);

    // Simulate async operation
    await Future.delayed(const Duration(milliseconds: 500));

    final status = WebOAuthStatus.checkWebOAuthStatus();

    setState(() {
      _status = status;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('Web OAuth diagnostic is only available on web platform'),
        ),
      );
    }

    if (_isLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Checking web OAuth configuration...'),
            ],
          ),
        ),
      );
    }

    if (_status == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('Failed to check web OAuth status'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildOverallStatus(),
            const SizedBox(height: 16),
            _buildIssuesSection(),
            const SizedBox(height: 16),
            _buildPlatformsSection(),
            const SizedBox(height: 16),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(
          kIsWeb ? Icons.web : Icons.mobile_friendly,
          color: Theme.of(context).primaryColor,
        ),
        const SizedBox(width: 8),
        const Text(
          'Web OAuth Configuration',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _checkStatus,
          tooltip: 'Refresh status',
        ),
      ],
    );
  }

  Widget _buildOverallStatus() {
    final isConfigured = _status!['isConfigured'] as bool;
    final domain = _status!['domain'] as String;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isConfigured ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isConfigured ? Colors.green.shade200 : Colors.orange.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isConfigured ? Icons.check_circle : Icons.warning,
                color: isConfigured ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Text(
                isConfigured
                    ? 'Configuration Complete'
                    : 'Configuration Required',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isConfigured
                      ? Colors.green.shade700
                      : Colors.orange.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Domain: $domain'),
        ],
      ),
    );
  }

  Widget _buildIssuesSection() {
    final issues = _status!['issues'] as List<String>;
    final warnings = _status!['warnings'] as List<String>;

    if (issues.isEmpty && warnings.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Issues & Warnings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...issues.map((issue) => _buildIssueItem(issue, true)),
        ...warnings.map((warning) => _buildIssueItem(warning, false)),
      ],
    );
  }

  Widget _buildIssueItem(String message, bool isError) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error : Icons.warning,
            size: 16,
            color: isError ? Colors.red : Colors.orange,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isError ? Colors.red.shade700 : Colors.orange.shade700,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlatformsSection() {
    final platforms = _status!['platforms'] as Map<String, dynamic>;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Platform Status',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...platforms.entries
            .map((entry) => _buildPlatformItem(entry.key, entry.value)),
      ],
    );
  }

  Widget _buildPlatformItem(String platform, Map<String, dynamic> status) {
    final isConfigured = status['configured'] as bool? ?? false;
    final isSupported = status['supported'] as bool? ?? false;
    final redirectUri = status['redirectUri'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isConfigured && isSupported
                      ? Icons.check_circle
                      : Icons.error,
                  color:
                      isConfigured && isSupported ? Colors.green : Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  platform.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isConfigured && isSupported
                        ? Colors.green.shade100
                        : Colors.red.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isConfigured && isSupported ? 'Ready' : 'Not Ready',
                    style: TextStyle(
                      fontSize: 12,
                      color: isConfigured && isSupported
                          ? Colors.green.shade700
                          : Colors.red.shade700,
                    ),
                  ),
                ),
              ],
            ),
            if (redirectUri.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Redirect URI: $redirectUri',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    final issues = _status!['issues'] as List<String>;

    return Column(
      children: [
        if (issues.isNotEmpty) ...[
          ElevatedButton.icon(
            onPressed: () => _showTroubleshooting(),
            icon: const Icon(Icons.help),
            label: const Text('Get Troubleshooting Help'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          onPressed: () => _showSetupInstructions(),
          icon: const Icon(Icons.settings),
          label: const Text('View Setup Instructions'),
        ),
      ],
    );
  }

  void _showTroubleshooting() {
    final issues = _status!['issues'] as List<String>;
    final steps = WebOAuthStatus.getTroubleshootingSteps(issues);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Troubleshooting Steps'),
        content: SingleChildScrollView(
          child: Text(steps),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showSetupInstructions() {
    final instructions = WebOAuthStatus.getSetupInstructions();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Web OAuth Setup Instructions'),
        content: SingleChildScrollView(
          child: Text(instructions),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
