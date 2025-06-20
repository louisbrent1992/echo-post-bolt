import 'package:flutter/material.dart';

class UnifiedMediaButtons extends StatelessWidget {
  final VoidCallback onDirectorySelection;
  final VoidCallback onMediaSelection;
  final bool hasMedia;
  final String? directoryName;

  const UnifiedMediaButtons({
    super.key,
    required this.onDirectorySelection,
    required this.onMediaSelection,
    this.hasMedia = false,
    this.directoryName,
  });

  @override
  Widget build(BuildContext context) {
    // Grid spacing constants
    const double _spacing2 = 12.0;
    const double _spacing3 = 18.0;

    return Container(
      width: double.infinity,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: _spacing3),
      child: Row(
        children: [
          // Directory selection button (left side)
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.folder_open, size: 16),
              label: Text(
                directoryName ?? 'Select Directory',
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: onDirectorySelection,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF0080),
                side: const BorderSide(color: Color(0xFFFF0080)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_spacing2),
                ),
              ),
            ),
          ),

          const SizedBox(width: _spacing2), // Gap between buttons

          // Media selection button (right side)
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.photo_library, size: 16),
              label: Text(
                hasMedia ? 'Change Media' : 'Select Media',
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              onPressed: onMediaSelection,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF0080),
                side: const BorderSide(color: Color(0xFFFF0080)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_spacing2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
