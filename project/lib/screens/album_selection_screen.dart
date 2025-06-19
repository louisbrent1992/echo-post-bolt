import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../services/firestore_service.dart';
import '../services/media_coordinator.dart';

class AlbumSelectionScreen extends StatefulWidget {
  const AlbumSelectionScreen({super.key});

  @override
  State<AlbumSelectionScreen> createState() => _AlbumSelectionScreenState();
}

class _AlbumSelectionScreenState extends State<AlbumSelectionScreen> {
  bool _isLoading = true;
  List<AssetPathEntity> _availableAlbums = [];
  Set<String> _selectedAlbumIds = {};
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final mediaCoordinator =
          Provider.of<MediaCoordinator>(context, listen: false);
      final firestoreService =
          Provider.of<FirestoreService>(context, listen: false);

      // Get all available albums through MediaCoordinator
      final albums = await mediaCoordinator.getAvailableAlbums();

      // Get currently selected album IDs
      final selectedIds = await firestoreService.getSelectedMediaAlbums();

      setState(() {
        _availableAlbums = albums;
        _selectedAlbumIds = selectedIds.toSet();

        // If no albums are selected, default to "All Photos"
        if (_selectedAlbumIds.isEmpty && albums.isNotEmpty) {
          try {
            final allPhotosAlbum = albums.firstWhere(
              (album) => album.isAll,
              orElse: () => albums.first,
            );
            _selectedAlbumIds.add(allPhotosAlbum.id);
          } catch (e) {
            // If we can't find "All Photos", select the first album
            if (albums.isNotEmpty) {
              _selectedAlbumIds.add(albums.first.id);
            }
          }
        }

        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load albums: $e')),
        );
      }
    }
  }

  Future<void> _saveSelection() async {
    if (_selectedAlbumIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one album')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final firestoreService =
          Provider.of<FirestoreService>(context, listen: false);
      final mediaCoordinator =
          Provider.of<MediaCoordinator>(context, listen: false);

      // Save the selected album IDs to Firestore
      await firestoreService
          .updateSelectedMediaAlbums(_selectedAlbumIds.toList());

      // Re-initialize the media search service with new albums
      await mediaCoordinator.reinitializeWithAlbums(
          _selectedAlbumIds.toList(), firestoreService);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Album selection saved successfully!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save selection: $e')),
        );
      }
    }
  }

  void _toggleAlbumSelection(String albumId) {
    setState(() {
      if (_selectedAlbumIds.contains(albumId)) {
        _selectedAlbumIds.remove(albumId);
      } else {
        _selectedAlbumIds.add(albumId);
      }
    });
  }

  Widget _buildAlbumTile(AssetPathEntity album) {
    final isSelected = _selectedAlbumIds.contains(album.id);
    final isAllPhotos = album.isAll;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: CheckboxListTile(
        value: isSelected,
        onChanged: (bool? value) {
          _toggleAlbumSelection(album.id);
        },
        title: Row(
          children: [
            Expanded(
              child: Text(
                album.name,
                style: TextStyle(
                  fontWeight: isAllPhotos ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (isAllPhotos)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  'Default',
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
        subtitle: FutureBuilder<int>(
          future: album.assetCountAsync,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Text('Loading...');
            }

            if (snapshot.hasError) {
              return const Text('Error loading count');
            }

            final count = snapshot.data ?? 0;
            return Text(
              '$count ${count == 1 ? 'item' : 'items'}',
              style: Theme.of(context).textTheme.bodySmall,
            );
          },
        ),
        secondary: FutureBuilder<AssetEntity?>(
          future: _getAlbumThumbnail(album),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.photo_library),
              );
            }

            if (snapshot.hasError || !snapshot.hasData) {
              return Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.photo_library),
              );
            }

            final asset = snapshot.data!;
            return FutureBuilder(
              future: asset.thumbnailDataWithSize(const ThumbnailSize(56, 56)),
              builder: (context, thumbnailSnapshot) {
                if (!thumbnailSnapshot.hasData) {
                  return Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.photo_library),
                  );
                }

                return Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    image: DecorationImage(
                      image: MemoryImage(thumbnailSnapshot.data!),
                      fit: BoxFit.cover,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<AssetEntity?> _getAlbumThumbnail(AssetPathEntity album) async {
    try {
      final assets = await album.getAssetListRange(start: 0, end: 1);
      return assets.isNotEmpty ? assets.first : null;
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Media Folders'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveSelection,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Header with explanation
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Albums to Search',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Choose which photo and video albums EchoPost should search when you ask for media. For privacy, only selected albums will be indexed.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_selectedAlbumIds.length} album${_selectedAlbumIds.length == 1 ? '' : 's'} selected',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ],
                  ),
                ),

                // Albums list
                Expanded(
                  child: _availableAlbums.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.photo_library_outlined,
                                size: 64,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No albums found',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Please check your photo permissions',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color:
                                          Theme.of(context).colorScheme.outline,
                                    ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 8, bottom: 16),
                          itemCount: _availableAlbums.length,
                          itemBuilder: (context, index) {
                            final album = _availableAlbums[index];
                            return _buildAlbumTile(album);
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
