import 'package:flutter/material.dart';
import '../constants/typography.dart';

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
    const double spacing2 = 12.0;

    return Container(
      width: double.infinity,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 20),
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
                  fontSize: AppTypography.body,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: onDirectorySelection,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF0080),
                side:
                    BorderSide(color: const Color(0xFFFF0080).withOpacity(0.3)),
                backgroundColor: const Color(0xFFFF0080).withOpacity(0.1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(spacing2),
                ),
              ),
            ),
          ),

          const SizedBox(width: spacing2), // Gap between buttons

          // Media selection button (right side)
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.photo_library, size: 16),
              label: Text(
                hasMedia ? 'Change Media' : 'Select Media',
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: AppTypography.body,
                ),
              ),
              onPressed: onMediaSelection,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF0080),
                side:
                    BorderSide(color: const Color(0xFFFF0080).withOpacity(0.3)),
                backgroundColor: const Color(0xFFFF0080).withOpacity(0.1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(spacing2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
