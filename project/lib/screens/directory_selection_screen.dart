import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/media_coordinator.dart';
import '../services/directory_service.dart'; // For MediaDirectory class
import 'package:provider/provider.dart';
import '../widgets/directory_picker_sheet.dart';

class DirectorySelectionScreen extends StatefulWidget {
  const DirectorySelectionScreen({super.key});

  @override
  State<DirectorySelectionScreen> createState() =>
      _DirectorySelectionScreenState();
}

class _DirectorySelectionScreenState extends State<DirectorySelectionScreen> {
  List<MediaDirectory> _directories = [];
  MediaCoordinator? _mediaCoordinator;
  bool _isLoading = true;
  bool _isCustomEnabled = false;
  bool _hasChanges = false; // Track if any changes were made

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  Future<void> _initializeScreen() async {
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
        _directories =
            List<MediaDirectory>.from(_mediaCoordinator!.directories);
        _isCustomEnabled = _mediaCoordinator!.isCustomDirectoriesEnabled;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initialize screen: $e')),
        );
      }
    }
  }

  Future<void> _toggleCustomDirectories(bool enabled) async {
    if (_mediaCoordinator == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      if (kDebugMode) {
        print(
            '🔄 DirectorySelectionScreen: Toggling custom directories to: $enabled');
      }

      await _mediaCoordinator!.setCustomDirectoriesEnabled(enabled);

      // ========== PHASE 4: USE CONSOLIDATED NOTIFICATION SYSTEM ==========
      // Notify MediaCoordinator of the directory mode change
      await _mediaCoordinator!.notifyMediaChange(
        forceFullRefresh: true,
        source: 'DirectorySelectionScreen.toggleCustomDirectories',
      );

      setState(() {
        _isCustomEnabled = enabled;
        _hasChanges = true; // Mark that changes were made
        _isLoading = false;
      });

      if (kDebugMode) {
        print(
            '✅ DirectorySelectionScreen: Custom directories toggled successfully - _hasChanges set to true');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to toggle custom directories: $e')),
        );
      }
    }
  }

  Future<void> _toggleDirectory(String directoryId, bool enabled) async {
    if (_mediaCoordinator == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      if (kDebugMode) {
        print(
            '🔄 DirectorySelectionScreen: Toggling directory $directoryId to: $enabled');
      }

      await _mediaCoordinator!.updateDirectoryEnabled(directoryId, enabled);

      // ========== PHASE 4: USE CONSOLIDATED NOTIFICATION SYSTEM ==========
      // Get the directory path for targeted refresh
      final directory = _directories.firstWhere((d) => d.id == directoryId);
      await _mediaCoordinator!.notifyMediaChange(
        changedDirectories: [directory.path],
        forceFullRefresh: false,
        source: 'DirectorySelectionScreen.toggleDirectory',
      );

      setState(() {
        _directories =
            List<MediaDirectory>.from(_mediaCoordinator!.directories);
        _hasChanges = true; // Mark that changes were made
        _isLoading = false;
      });

      if (kDebugMode) {
        print(
            '✅ DirectorySelectionScreen: Directory toggled successfully - _hasChanges set to true');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to toggle directory: $e')),
        );
      }
    }
  }

  Future<void> _removeDirectory(String directoryId) async {
    if (_mediaCoordinator == null) return;

    try {
      // Validate directory exists
      _directories.firstWhere(
        (d) => d.id == directoryId,
        orElse: () => throw Exception('Directory not found'),
      );

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Remove Directory'),
          content:
              const Text('Are you sure you want to remove this directory?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        await _mediaCoordinator!.removeDirectory(directoryId);

        setState(() {
          _directories =
              List<MediaDirectory>.from(_mediaCoordinator!.directories);
          _hasChanges = true; // Mark that changes were made
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove directory: $e')),
        );
      }
    }
  }

  Future<void> _showDirectoryPicker() async {
    if (_mediaCoordinator == null) return;

    try {
      final suggestions = await _mediaCoordinator!.getSuggestedDirectories();

      if (!mounted) return;

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) => DirectoryPickerSheet(
          suggestions: suggestions,
          onDirectorySelected: _addDirectory,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to show directory picker: $e')),
        );
      }
    }
  }

  Future<void> _addDirectory(String name, String path) async {
    if (_mediaCoordinator == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      if (kDebugMode) {
        print('🔄 DirectorySelectionScreen: Adding directory: $name at $path');
      }

      await _mediaCoordinator!.addCustomDirectory(name, path);

      // ========== PHASE 4: USE CONSOLIDATED NOTIFICATION SYSTEM ==========
      // Notify MediaCoordinator of the new directory
      await _mediaCoordinator!.notifyMediaChange(
        changedDirectories: [path],
        forceFullRefresh: false,
        source: 'DirectorySelectionScreen.addDirectory',
      );

      setState(() {
        _directories =
            List<MediaDirectory>.from(_mediaCoordinator!.directories);
        _hasChanges = true; // Mark that changes were made
        _isLoading = false;
      });

      if (kDebugMode) {
        print(
            '✅ DirectorySelectionScreen: Directory added successfully - _hasChanges set to true');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add directory: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent automatic pop to handle it manually
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop) {
          // Handle the pop manually and return the _hasChanges value
          if (kDebugMode) {
            print(
                '🔄 DirectorySelectionScreen: Returning to MediaSelectionScreen with _hasChanges: $_hasChanges');
          }
          Navigator.of(context).pop(_hasChanges);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Media Directories'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              // Always return the _hasChanges value when navigating back
              if (kDebugMode) {
                print(
                    '🔄 DirectorySelectionScreen: Manual back button pressed - returning with _hasChanges: $_hasChanges');
              }
              Navigator.of(context).pop(_hasChanges);
            },
          ),
          actions: [
            IconButton(
              onPressed: _showDirectoryPicker,
              icon: const Icon(Icons.add),
              tooltip: 'Add Custom Directory',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFFF0055),
                ),
              )
            : Column(
                children: [
                  // Mode toggle section
                  Container(
                    margin: const EdgeInsets.all(16),
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
                        const Row(
                          children: [
                            Icon(
                              Icons.folder_open,
                              color: Color(0xFFFF0055),
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Media Source',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          value: _isCustomEnabled,
                          onChanged: _toggleCustomDirectories,
                          title: const Text(
                            'Use Custom Directories',
                            style: TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            _isCustomEnabled
                                ? 'Scanning specific directories for media'
                                : 'Using photo albums (recommended)',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
                          ),
                          activeColor: const Color(0xFFFF0055),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),

                  // Directories list
                  if (_isCustomEnabled) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Icon(
                            Icons.folder,
                            color: Colors.white.withValues(alpha: 0.7),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Select Directories to Scan',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Column(
                        children: [
                          // Existing directories list
                          Expanded(
                            child: ListView.builder(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _directories.length,
                              itemBuilder: (context, index) {
                                final directory = _directories[index];
                                return _buildDirectoryTile(directory);
                              },
                            ),
                          ),

                          // Add Custom Directory section at the bottom
                          _buildAddCustomDirectorySection(),
                        ],
                      ),
                    ),
                  ] else ...[
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.photo_library,
                              color: Colors.white.withValues(alpha: 0.4),
                              size: 64,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Album Mode Active',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 32),
                              child: Text(
                                'The app will use photo albums from your device\'s gallery. This is the recommended mode for most users.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _buildDirectoryTile(MediaDirectory directory) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: directory.isEnabled
            ? const Color(0xFFFF0055).withValues(alpha: 0.1)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: directory.isEnabled
              ? const Color(0xFFFF0055).withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: ListTile(
        leading: Icon(
          directory.isDefault ? Icons.folder_special : Icons.folder,
          color: directory.isEnabled
              ? const Color(0xFFFF0055)
              : Colors.white.withValues(alpha: 0.4),
        ),
        title: Text(
          directory.displayName,
          style: TextStyle(
            color: directory.isEnabled
                ? Colors.white
                : Colors.white.withValues(alpha: 0.6),
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          directory.path,
          style: TextStyle(
            color: directory.isEnabled
                ? Colors.white.withValues(alpha: 0.7)
                : Colors.white.withValues(alpha: 0.4),
            fontSize: 12,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: directory.isEnabled,
              onChanged: (enabled) => _toggleDirectory(directory.id, enabled),
              activeColor: const Color(0xFFFF0055),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            if (!directory.isDefault) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _removeDirectory(directory.id),
                icon: const Icon(Icons.delete, size: 18),
                color: Colors.red.withValues(alpha: 0.7),
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAddCustomDirectorySection() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFF0055).withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(
                  Icons.add_circle_outline,
                  color: Color(0xFFFF0055),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Add Custom Directory',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Specify any directory path on your device',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                // Browse button
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _showDirectoryPicker,
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Browse Folders'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color(0xFFFF0055).withValues(alpha: 0.1),
                      foregroundColor: const Color(0xFFFF0055),
                      side: BorderSide(
                        color: const Color(0xFFFF0055).withValues(alpha: 0.3),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Manual entry button
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _showDirectoryPicker,
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Enter Path'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
