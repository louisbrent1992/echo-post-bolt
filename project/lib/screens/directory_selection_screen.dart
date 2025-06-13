import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../services/directory_service.dart';
import 'package:provider/provider.dart';

class DirectorySelectionScreen extends StatefulWidget {
  const DirectorySelectionScreen({super.key});

  @override
  State<DirectorySelectionScreen> createState() =>
      _DirectorySelectionScreenState();
}

class _DirectorySelectionScreenState extends State<DirectorySelectionScreen> {
  DirectoryService? _directory_service;
  bool _isLoading = true;
  final bool _isSaving = false;
  List<MediaDirectory> _directories = [];
  bool _customDirectoriesEnabled = false;

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
        _directories =
            List<MediaDirectory>.from(_directory_service!.directories);
        _customDirectoriesEnabled =
            _directory_service!.isCustomDirectoriesEnabled;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load directories: $e')),
        );
      }
    }
  }

  Future<void> _toggleCustomDirectories(bool enabled) async {
    if (_directory_service == null) return;

    setState(() {
      _customDirectoriesEnabled = enabled;
    });

    try {
      await _directory_service!.setCustomDirectoriesEnabled(enabled);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update setting: $e')),
        );
      }
    }
  }

  Future<void> _toggleDirectory(String directoryId, bool enabled) async {
    if (_directory_service == null) return;

    try {
      await _directory_service!.updateDirectoryEnabled(directoryId, enabled);

      setState(() {
        _directories =
            List<MediaDirectory>.from(_directory_service!.directories);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update directory: $e')),
        );
      }
    }
  }

  Future<void> _showAddDirectoryDialog() async {
    await _showEnhancedAddDirectoryDialog();
  }

  Future<void> _removeDirectory(String directoryId) async {
    if (_directory_service == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Directory'),
        content: const Text('Are you sure you want to remove this directory?'),
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
      try {
        await _directory_service!.removeDirectory(directoryId);

        setState(() {
          _directories =
              List<MediaDirectory>.from(_directory_service!.directories);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Directory removed successfully!')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to remove directory: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Media Directories'),
        actions: [
          IconButton(
            onPressed: _showAddDirectoryDialog,
            icon: const Icon(Icons.add),
            tooltip: 'Add Custom Directory',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFFF0080),
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
                      Row(
                        children: [
                          Icon(
                            Icons.folder_open,
                            color: const Color(0xFFFF0080),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          const Text(
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
                        value: _customDirectoriesEnabled,
                        onChanged: _toggleCustomDirectories,
                        title: const Text(
                          'Use Custom Directories',
                          style: TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          _customDirectoriesEnabled
                              ? 'Scanning specific directories for media'
                              : 'Using photo albums (recommended)',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                        ),
                        activeColor: const Color(0xFFFF0080),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),

                // Directories list
                if (_customDirectoriesEnabled) ...[
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
                            padding: const EdgeInsets.symmetric(horizontal: 16),
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
                            padding: const EdgeInsets.symmetric(horizontal: 32),
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
    );
  }

  Widget _buildDirectoryTile(MediaDirectory directory) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: directory.isEnabled
            ? const Color(0xFFFF0080).withValues(alpha: 0.1)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: directory.isEnabled
              ? const Color(0xFFFF0080).withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: ListTile(
        leading: Icon(
          directory.isDefault ? Icons.folder_special : Icons.folder,
          color: directory.isEnabled
              ? const Color(0xFFFF0080)
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
              activeColor: const Color(0xFFFF0080),
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
          color: const Color(0xFFFF0080).withValues(alpha: 0.3),
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
                Icon(
                  Icons.add_circle_outline,
                  color: const Color(0xFFFF0080),
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
                    onPressed: _browseForDirectory,
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Browse Folders'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color(0xFFFF0080).withValues(alpha: 0.1),
                      foregroundColor: const Color(0xFFFF0080),
                      side: BorderSide(
                        color: const Color(0xFFFF0080).withValues(alpha: 0.3),
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
                    onPressed: _showEnhancedAddDirectoryDialog,
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

  Future<void> _browseForDirectory() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        // On mobile, show path suggestions since direct browsing is limited
        await _showDirectorySuggestions();
      } else {
        // On desktop platforms, use file picker for directory selection
        final selectedDirectory = await FilePicker.platform.getDirectoryPath();

        if (selectedDirectory != null) {
          await _addDirectoryWithValidation(
            'Custom Directory',
            selectedDirectory,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to browse directories: $e')),
        );
      }
    }
  }

  Future<void> _showDirectorySuggestions() async {
    if (_directory_service == null) return;

    try {
      final suggestions = await _directory_service!.getSuggestedDirectories();

      if (!mounted) return;

      final selectedPath = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text(
            'Suggested Directories',
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Select a directory or use "Enter Path" for custom locations:',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 16),
                if (suggestions.isEmpty)
                  const Text(
                    'No accessible directories found. Use "Enter Path" to specify a custom directory.',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    itemCount: suggestions.length,
                    itemBuilder: (context, index) {
                      final suggestion = suggestions[index];
                      return ListTile(
                        leading: const Icon(
                          Icons.folder,
                          color: Color(0xFFFF0080),
                          size: 20,
                        ),
                        title: Text(
                          suggestion.split('/').last,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          suggestion,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => Navigator.pop(context, suggestion),
                        dense: true,
                      );
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'manual'),
              child: const Text(
                'Enter Path',
                style: TextStyle(color: Color(0xFFFF0080)),
              ),
            ),
          ],
        ),
      );

      if (selectedPath == 'manual') {
        await _showEnhancedAddDirectoryDialog();
      } else if (selectedPath != null && selectedPath.isNotEmpty) {
        await _addDirectoryWithValidation(
          selectedPath.split('/').last,
          selectedPath,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to get suggestions: $e')),
        );
      }
    }
  }

  Future<void> _showEnhancedAddDirectoryDialog() async {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController pathController = TextEditingController();

    // Pre-fill with platform-appropriate example
    if (Platform.isAndroid) {
      pathController.text = '/storage/emulated/0/Pictures/';
    } else if (Platform.isIOS) {
      pathController.text = 'NSDocumentDirectory/Photos/';
    }

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Add Custom Directory',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Specify a custom directory to scan for media files:',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Display Name',
                labelStyle:
                    TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                hintText: 'e.g., "Instagram Photos"',
                hintStyle:
                    TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                border: OutlineInputBorder(
                  borderSide:
                      BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide:
                      BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFFF0080)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: pathController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Directory Path',
                labelStyle:
                    TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                hintText: Platform.isAndroid
                    ? '/storage/emulated/0/Pictures/YourFolder'
                    : 'NSDocumentDirectory/YourFolder',
                hintStyle:
                    TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                border: OutlineInputBorder(
                  borderSide:
                      BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide:
                      BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFFF0080)),
                ),
                helperText: Platform.isAndroid
                    ? 'Full path to Android directory'
                    : 'iOS directory identifier',
                helperStyle:
                    TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            Text(
              '💡 Tip: Use the "Browse Folders" button for suggestions',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              final path = pathController.text.trim();
              if (name.isNotEmpty && path.isNotEmpty) {
                Navigator.pop(context, {'name': name, 'path': path});
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF0080),
              foregroundColor: Colors.white,
            ),
            child: const Text('Add Directory'),
          ),
        ],
      ),
    );

    if (result != null) {
      await _addDirectoryWithValidation(
        result['name']!,
        result['path']!,
      );
    }
  }

  Future<void> _addDirectoryWithValidation(String name, String path) async {
    if (_directory_service == null) return;

    try {
      await _directory_service!.addCustomDirectory(name, path);

      setState(() {
        _directories =
            List<MediaDirectory>.from(_directory_service!.directories);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Added directory: $name'),
            backgroundColor: Colors.green.withValues(alpha: 0.8),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to add directory: $e'),
            backgroundColor: Colors.red.withValues(alpha: 0.8),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }
}
