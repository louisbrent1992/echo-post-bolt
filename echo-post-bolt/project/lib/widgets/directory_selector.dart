import 'package:flutter/material.dart';
import '../services/media_coordinator.dart';
import '../screens/directory_selection_screen.dart';
import 'package:provider/provider.dart';
import '../constants/typography.dart';

class DirectorySelector extends StatefulWidget {
  const DirectorySelector({super.key});

  @override
  State<DirectorySelector> createState() => _DirectorySelectorState();
}

class _DirectorySelectorState extends State<DirectorySelector> {
  MediaCoordinator? _mediaCoordinator;
  bool _isLoading = true;
  bool _isCustomEnabled = false;
  int _enabledCount = 0;

  @override
  void initState() {
    super.initState();
    _initializeSelector();
  }

  Future<void> _initializeSelector() async {
    setState(() {
      _isLoading = true;
    });

    try {
      _mediaCoordinator = Provider.of<MediaCoordinator>(context, listen: false);

      // MediaCoordinator should already be initialized by ServiceInitializationWrapper
      if (!_mediaCoordinator!.isInitialized) {
        await _mediaCoordinator!.initialize();
      }

      setState(() {
        _isLoading = false;
        _isCustomEnabled = _mediaCoordinator!.isCustomDirectoriesEnabled;
        _enabledCount = _mediaCoordinator!.enabledDirectories.length;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _openDirectorySelection() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const DirectorySelectionScreen(),
      ),
    );

    // Refresh status after returning from directory selection
    if (result != null || mounted) {
      await _initializeSelector();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: _openDirectorySelection,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isCustomEnabled ? Icons.folder_open : Icons.photo_library,
              color: const Color(0xFFFF0080),
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _getStatusText(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: AppTypography.small,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.white.withValues(alpha: 0.5),
              size: 12,
            ),
          ],
        ),
      ),
    );
  }

  String _getStatusText() {
    if (_isCustomEnabled) {
      if (_enabledCount == 0) {
        return 'No directories selected';
      } else if (_enabledCount == 1) {
        return '1 directory selected';
      } else {
        return '$_enabledCount directories selected';
      }
    } else {
      return 'Using photo albums';
    }
  }
}
