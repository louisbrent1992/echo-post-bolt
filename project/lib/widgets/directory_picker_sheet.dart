import 'package:flutter/material.dart';
import 'dart:io';

class DirectoryPickerSheet extends StatelessWidget {
  final List<String> suggestions;
  final Function(String name, String path) onDirectorySelected;

  const DirectoryPickerSheet({
    super.key,
    required this.suggestions,
    required this.onDirectorySelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(
                  Icons.folder_open,
                  color: Color(0xFFFF0080),
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Select Directory',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  color: Colors.white.withAlpha((0.7 * 255).round()),
                ),
              ],
            ),
          ),

          // Suggestions list
          if (suggestions.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(
                    Icons.folder_off,
                    size: 48,
                    color: Colors.white.withAlpha((0.3 * 255).round()),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No accessible directories found',
                    style: TextStyle(
                      color: Colors.white.withAlpha((0.7 * 255).round()),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Try entering a path manually',
                    style: TextStyle(
                      color: Colors.white.withAlpha((0.5 * 255).round()),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: suggestions.length,
                itemBuilder: (context, index) {
                  final path = suggestions[index];
                  final name = path.split(Platform.pathSeparator).last;
                  return ListTile(
                    leading: const Icon(
                      Icons.folder,
                      color: Color(0xFFFF0080),
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      path,
                      style: TextStyle(
                        color: Colors.white.withAlpha((0.7 * 255).round()),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      onDirectorySelected(name, path);
                    },
                  );
                },
              ),
            ),

          // Manual entry section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Divider(color: Colors.white24),
                const SizedBox(height: 16),
                Text(
                  'Or enter a path manually:',
                  style: TextStyle(
                    color: Colors.white.withAlpha((0.7 * 255).round()),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _showManualEntryDialog(context);
                  },
                  icon: const Icon(Icons.edit),
                  label: const Text('Enter Custom Path'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        const Color(0xFFFF0080).withAlpha((0.1 * 255).round()),
                    foregroundColor: const Color(0xFFFF0080),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                          color: const Color(0xFFFF0080)
                              .withAlpha((0.3 * 255).round())),
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

  Future<void> _showManualEntryDialog(BuildContext context) async {
    final nameController = TextEditingController();
    final pathController = TextEditingController();

    // Pre-fill with platform-appropriate example
    if (Platform.isAndroid) {
      pathController.text = '/storage/emulated/0/Pictures/';
    } else if (Platform.isIOS) {
      pathController.text = 'NSDocumentDirectory/Photos/';
    }

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text(
          'Enter Directory Details',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Display Name',
                labelStyle: TextStyle(
                    color: Colors.white.withAlpha((0.7 * 255).round())),
                hintText: 'e.g., "Instagram Photos"',
                hintStyle: TextStyle(
                    color: Colors.white.withAlpha((0.5 * 255).round())),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                      color: Colors.white.withAlpha((0.3 * 255).round())),
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
                labelStyle: TextStyle(
                    color: Colors.white.withAlpha((0.7 * 255).round())),
                hintText: Platform.isAndroid
                    ? '/storage/emulated/0/Pictures/YourFolder'
                    : 'NSDocumentDirectory/YourFolder',
                hintStyle: TextStyle(
                    color: Colors.white.withAlpha((0.5 * 255).round())),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                      color: Colors.white.withAlpha((0.3 * 255).round())),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFFF0080)),
                ),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style:
                  TextStyle(color: Colors.white.withAlpha((0.7 * 255).round())),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              final path = pathController.text.trim();
              if (name.isNotEmpty && path.isNotEmpty) {
                Navigator.pop(context);
                onDirectorySelected(name, path);
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
      onDirectorySelected(result['name']!, result['path']!);
    }
  }
}
