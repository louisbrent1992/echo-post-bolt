import 'package:flutter/material.dart';
import '../services/directory_service.dart';
import '../screens/directory_selection_screen.dart';
import 'package:provider/provider.dart';

class DirectorySelector extends StatefulWidget {
  const DirectorySelector({super.key});

  @override
  State<DirectorySelector> createState() => _DirectorySelectorState();
}

class _DirectorySelectorState extends State<DirectorySelector> {
  DirectoryService? _directory_service;
  bool _isLoading = true;
  bool _customDirectoriesEnabled = false;
  int _enabledDirectoriesCount = 0;

  @override
  void initState() {
    super.initState();
    _initializeService();
  }

  Future<void> _initializeService() async {
    setState(() {
      _isLoading = true;
    });

    try {
      _directory_service =
          Provider.of<DirectoryService>(context, listen: false);
      await _directory_service!.initialize();

      setState(() {
        _customDirectoriesEnabled =
            _directory_service!.isCustomDirectoriesEnabled;
        _enabledDirectoriesCount =
            _directory_service!.enabledDirectories.length;
        _isLoading = false;
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
      await _initializeService();
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
              _customDirectoriesEnabled
                  ? Icons.folder_open
                  : Icons.photo_library,
              color: const Color(0xFFFF0080),
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _getStatusText(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
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
    if (_customDirectoriesEnabled) {
      if (_enabledDirectoriesCount == 0) {
        return 'No directories selected';
      } else if (_enabledDirectoriesCount == 1) {
        return '1 directory selected';
      } else {
        return '$_enabledDirectoriesCount directories selected';
      }
    } else {
      return 'Using photo albums';
    }
  }
}
