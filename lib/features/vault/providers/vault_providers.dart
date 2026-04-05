import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute/core/models/thing.dart';
import 'package:parachute/core/providers/feature_flags_provider.dart'
    show aiServerUrlProvider;
import 'package:parachute/core/services/tag_service.dart';
import 'package:parachute/features/daily/journal/providers/journal_providers.dart';

/// Trigger to refresh vault data.
final vaultRefreshTriggerProvider = StateProvider<int>((ref) => 0);

/// Search query for the vault tab.
final vaultSearchQueryProvider = StateProvider<String>((ref) => '');

/// Active tag filter (null = show all).
final vaultTagFilterProvider = StateProvider<String?>((ref) => null);

/// Fetch all tags with counts from the server.
final vaultTagsProvider = FutureProvider.autoDispose<List<TagInfo>>((ref) async {
  ref.watch(vaultRefreshTriggerProvider);
  await ref.watch(aiServerUrlProvider.future);
  final tagService = ref.watch(tagServiceProvider);
  return tagService.listTags();
});

/// Search notes across the full vault.
final vaultSearchProvider = FutureProvider.autoDispose<List<Note>?>((ref) async {
  final query = ref.watch(vaultSearchQueryProvider);
  if (query.trim().isEmpty) return null;
  await ref.watch(aiServerUrlProvider.future);
  final api = ref.watch(graphApiServiceProvider);
  return api.searchNotes(query);
});

/// Browse notes filtered by tag. Shows recent notes when no tag is selected.
final vaultNotesProvider = FutureProvider.autoDispose<List<Note>>((ref) async {
  ref.watch(vaultRefreshTriggerProvider);
  await ref.watch(aiServerUrlProvider.future);
  final api = ref.watch(graphApiServiceProvider);
  final tagFilter = ref.watch(vaultTagFilterProvider);

  final notes = await api.queryNotes(
    tag: tagFilter,
    sort: 'desc',
    limit: 50,
  );

  if (notes != null) {
    try {
      final cache = await ref.read(noteLocalCacheProvider.future);
      cache.putNotes(notes);
    } catch (e) {
      debugPrint('[VaultProviders] Cache write failed: $e');
    }
    return notes;
  }

  // Offline fallback
  try {
    final cache = await ref.read(noteLocalCacheProvider.future);
    if (tagFilter != null) {
      return cache.getNotesWithTag(tagFilter);
    }
    return [];
  } catch (e) {
    debugPrint('[VaultProviders] Cache read failed: $e');
    return [];
  }
});
