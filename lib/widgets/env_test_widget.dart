import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/json_env_service.dart';

/// Test widget to verify JSON environment service functionality
class EnvTestWidget extends StatefulWidget {
  const EnvTestWidget({super.key});

  @override
  State<EnvTestWidget> createState() => _EnvTestWidgetState();
}

class _EnvTestWidgetState extends State<EnvTestWidget> {
  Map<String, dynamic>? _envStatus;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEnvStatus();
  }

  Future<void> _loadEnvStatus() async {
    setState(() => _isLoading = true);

    // Wait a bit for initialization
    await Future.delayed(const Duration(milliseconds: 500));

    final status = JsonEnvService.getEnvironmentStatus();

    setState(() {
      _envStatus = status;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.settings,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Environment Test',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadEnvStatus,
                  tooltip: 'Refresh status',
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_envStatus != null)
              _buildEnvStatus()
            else
              const Text('Failed to load environment status'),
          ],
        ),
      ),
    );
  }

  Widget _buildEnvStatus() {
    final status = _envStatus!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStatusItem('Initialized', status['isInitialized'] ?? false),
        _buildStatusItem('Total Variables', '${status['totalVars'] ?? 0}'),
        _buildStatusItem('Environment', status['environment'] ?? 'unknown'),
        _buildStatusItem('Debug Mode', status['debugMode'] ?? false),
        const SizedBox(height: 16),
        const Text(
          'Platform Configurations',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ..._buildPlatformStatuses(status['platforms'] ?? {}),
        const SizedBox(height: 16),
        _buildSampleVars(),
      ],
    );
  }

  Widget _buildStatusItem(String label, dynamic value) {
    final isBool = value is bool;
    final color = isBool ? (value ? Colors.green : Colors.red) : Colors.blue;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            isBool ? (value ? Icons.check_circle : Icons.error) : Icons.info,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Text('$label: '),
          Text(
            value.toString(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPlatformStatuses(Map<String, dynamic> platforms) {
    return platforms.entries.map((entry) {
      final platform = entry.key;
      final config = entry.value as Map<String, dynamic>;
      final isConfigured = config['configured'] ?? false;

      return Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Icon(
                isConfigured ? Icons.check_circle : Icons.error,
                color: isConfigured ? Colors.green : Colors.red,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                platform.toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isConfigured
                      ? Colors.green.shade100
                      : Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isConfigured ? 'Ready' : 'Not Ready',
                  style: TextStyle(
                    fontSize: 10,
                    color: isConfigured
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  Widget _buildSampleVars() {
    final sampleVars = [
      'OPENAI_API_KEY',
      'TWITTER_CLIENT_ID',
      'TIKTOK_CLIENT_KEY',
      'NETLIFY_DOMAIN',
      'ENVIRONMENT',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sample Environment Variables',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...sampleVars.map((varName) {
          final value = JsonEnvService.get(varName);
          final displayValue = value != null
              ? (varName.contains('KEY') || varName.contains('SECRET')
                  ? '${value.substring(0, 8)}...'
                  : value)
              : 'Not set';

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              children: [
                Icon(
                  value != null ? Icons.check_circle : Icons.error,
                  size: 12,
                  color: value != null ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  '$varName: ',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  displayValue,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: value != null ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
