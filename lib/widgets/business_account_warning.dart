import 'package:flutter/material.dart';
import '../constants/social_platforms.dart';
import '../services/social_action_post_coordinator.dart';
import '../models/platform_target.dart';

class BusinessAccountWarning extends StatefulWidget {
  final SocialActionPostCoordinator coordinator;

  const BusinessAccountWarning({
    super.key,
    required this.coordinator,
  });

  @override
  State<BusinessAccountWarning> createState() => _BusinessAccountWarningState();
}

class _BusinessAccountWarningState extends State<BusinessAccountWarning> {
  final Map<String, List<SubAccount>> _subAccounts = {};
  final Map<String, bool> _loadingStates = {};
  final Map<String, SubAccount?> _selectedAccounts = {};

  @override
  void initState() {
    super.initState();
    _loadSubAccounts();
  }

  Future<void> _loadSubAccounts() async {
    final platformsRequiringBusiness =
        await widget.coordinator.getPlatformsRequiringBusinessAccount();

    for (final platform in platformsRequiringBusiness) {
      if (SocialPlatforms.requiresBusinessAccount(platform)) {
        setState(() {
          _loadingStates[platform] = true;
        });

        try {
          final accounts = await widget.coordinator.getSubAccounts(platform);
          setState(() {
            _subAccounts[platform] = accounts;
            _loadingStates[platform] = false;
          });
        } catch (e) {
          setState(() {
            _loadingStates[platform] = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final platformsRequiringBusiness = _subAccounts.keys.toList();

    if (platformsRequiringBusiness.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange.withValues(alpha: 0.8),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Select Page or Sub-Account',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Choose which account to post to for automated publishing:',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 12),
          ...platformsRequiringBusiness
              .map((platform) => _buildPlatformSelection(platform)),
        ],
      ),
    );
  }

  Widget _buildPlatformSelection(String platform) {
    final accounts = _subAccounts[platform] ?? [];
    final isLoading = _loadingStates[platform] ?? false;
    final selectedAccount = _selectedAccounts[platform];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                SocialPlatforms.getIcon(platform),
                color: SocialPlatforms.getColor(platform),
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                SocialPlatforms.getDisplayName(platform),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: SocialPlatforms.getColor(platform),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Loading accounts...',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            )
          else if (accounts.isEmpty)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Colors.red.withValues(alpha: 0.3),
                ),
              ),
              child: const Text(
                'No business accounts found. Manual sharing will be used.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.red,
                ),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                ),
              ),
              child: DropdownButtonFormField<SubAccount>(
                value: selectedAccount,
                decoration: const InputDecoration(
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: InputBorder.none,
                  hintText: 'Select account...',
                  hintStyle: TextStyle(color: Colors.white70),
                ),
                dropdownColor: const Color(0xFF1A1A1A),
                style: const TextStyle(color: Colors.white),
                items: accounts.map((account) {
                  return DropdownMenuItem<SubAccount>(
                    value: account,
                    child: Text(
                      account.name,
                      style: const TextStyle(color: Colors.white),
                    ),
                  );
                }).toList(),
                onChanged: (SubAccount? account) {
                  setState(() {
                    _selectedAccounts[platform] = account;
                  });

                  if (account != null) {
                    widget.coordinator.setSelectedSubAccount(platform, account);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}
