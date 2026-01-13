import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:parachute_daily/core/services/embedding/embedding_service.dart';
import 'package:parachute_daily/core/services/search/simple_text_search.dart';
import 'package:parachute_daily/features/journal/services/journal_service.dart';

/// Semantic search service using embeddings for conceptual search
///
/// Provides semantic/conceptual search in addition to keyword matching.
/// Falls back gracefully when embeddings are not available.
///
/// **Features:**
/// - Semantic search using embedding similarity
/// - Hybrid mode: combines keyword + semantic results
/// - Graceful fallback when model not ready
/// - Caches embeddings for faster repeat searches
class SemanticSearchService {
  final EmbeddingService _embeddingService;
  final JournalService _journalService;
  final SimpleTextSearchService _keywordSearch;

  /// Cache of entry embeddings: entryId -> embedding vector
  final Map<String, List<double>> _embeddingCache = {};

  /// Cache of entry content: entryId -> content (for snippet extraction)
  final Map<String, _CachedEntry> _entryCache = {};

  /// Whether cache has been built
  bool _cacheBuilt = false;

  SemanticSearchService({
    required EmbeddingService embeddingService,
    required JournalService journalService,
    required SimpleTextSearchService keywordSearch,
  })  : _embeddingService = embeddingService,
        _journalService = journalService,
        _keywordSearch = keywordSearch;

  /// Check if semantic search is available
  Future<bool> isAvailable() async {
    try {
      return await _embeddingService.isReady();
    } catch (e) {
      debugPrint('[SemanticSearch] Error checking availability: $e');
      return false;
    }
  }

  /// Perform hybrid search (keyword + semantic)
  ///
  /// Returns combined results from both keyword and semantic search,
  /// deduplicated and sorted by relevance.
  Future<List<SimpleSearchResult>> search(
    String query, {
    int limit = 30,
    bool semanticOnly = false,
    double semanticWeight = 0.6,
  }) async {
    if (query.trim().isEmpty) return [];

    final stopwatch = Stopwatch()..start();

    // Always do keyword search first (it's fast)
    final keywordResults = semanticOnly ? <SimpleSearchResult>[] : await _keywordSearch.search(query, limit: limit);

    // Try semantic search if available
    List<SimpleSearchResult> semanticResults = [];
    final isReady = await isAvailable();

    if (isReady) {
      try {
        semanticResults = await _semanticSearch(query, limit: limit);
        debugPrint('[SemanticSearch] Found ${semanticResults.length} semantic results');
      } catch (e) {
        debugPrint('[SemanticSearch] Semantic search failed: $e');
        // Continue with keyword results only
      }
    } else {
      debugPrint('[SemanticSearch] Embedding model not ready, using keyword search only');
    }

    // Merge and deduplicate results
    final merged = _mergeResults(
      keywordResults,
      semanticResults,
      semanticWeight: semanticWeight,
    );

    stopwatch.stop();
    debugPrint(
      '[SemanticSearch] Hybrid search completed in ${stopwatch.elapsedMilliseconds}ms '
      '(keyword: ${keywordResults.length}, semantic: ${semanticResults.length}, merged: ${merged.length})',
    );

    return merged.take(limit).toList();
  }

  /// Perform pure semantic search
  Future<List<SimpleSearchResult>> _semanticSearch(
    String query, {
    int limit = 30,
    double minSimilarity = 0.3,
  }) async {
    // Build cache if needed
    if (!_cacheBuilt) {
      await _buildEmbeddingCache();
    }

    if (_embeddingCache.isEmpty) {
      debugPrint('[SemanticSearch] No embeddings cached');
      return [];
    }

    // Embed the query
    final queryEmbedding = await _embeddingService.embed(query);

    // Calculate similarity with all cached entries
    final results = <SimpleSearchResult>[];

    for (final entry in _entryCache.entries) {
      final entryId = entry.key;
      final cached = entry.value;
      final embedding = _embeddingCache[entryId];

      if (embedding == null) continue;

      final similarity = _cosineSimilarity(queryEmbedding, embedding);

      if (similarity >= minSimilarity) {
        // Extract snippet around most relevant part
        final snippet = _extractSemanticSnippet(cached.content, query);

        results.add(SimpleSearchResult(
          id: entryId,
          type: 'journal',
          title: cached.title,
          snippet: snippet,
          fullContent: cached.content,
          date: cached.date,
          matchCount: 0, // Semantic search doesn't count keyword matches
          entryType: cached.entryType,
          similarityScore: similarity,
        ));
      }
    }

    // Sort by similarity (descending)
    results.sort((a, b) => (b.similarityScore ?? 0).compareTo(a.similarityScore ?? 0));

    return results.take(limit).toList();
  }

  /// Build embedding cache for all journal entries
  Future<void> _buildEmbeddingCache() async {
    debugPrint('[SemanticSearch] Building embedding cache...');
    final stopwatch = Stopwatch()..start();

    try {
      final dates = await _journalService.listJournalDates();
      int entryCount = 0;
      int embeddedCount = 0;

      // Process in batches
      const batchSize = 10;
      for (int i = 0; i < dates.length; i += batchSize) {
        final batch = dates.skip(i).take(batchSize).toList();
        final journals = await Future.wait(
          batch.map((date) => _journalService.loadDay(date)),
        );

        for (int j = 0; j < journals.length; j++) {
          final date = batch[j];
          final journal = journals[j];
          final dateStr = _formatDate(date);

          for (final entry in journal.entries) {
            if (entry.id == 'preamble' || entry.content.isEmpty) continue;

            entryCount++;
            final entryId = 'journal:$dateStr:${entry.id}';

            // Skip if already cached
            if (_embeddingCache.containsKey(entryId)) continue;

            // Cache entry metadata
            _entryCache[entryId] = _CachedEntry(
              title: entry.title.isNotEmpty ? entry.title : 'Entry',
              content: entry.content,
              date: date,
              entryType: entry.type.name,
            );

            // Generate embedding (truncate content if too long)
            try {
              final textToEmbed = entry.content.length > 2000
                  ? entry.content.substring(0, 2000)
                  : entry.content;
              final embedding = await _embeddingService.embed(textToEmbed);
              _embeddingCache[entryId] = embedding;
              embeddedCount++;
            } catch (e) {
              debugPrint('[SemanticSearch] Failed to embed entry $entryId: $e');
            }
          }
        }
      }

      _cacheBuilt = true;
      stopwatch.stop();
      debugPrint(
        '[SemanticSearch] Cache built: $embeddedCount/$entryCount entries '
        'in ${stopwatch.elapsedMilliseconds}ms',
      );
    } catch (e) {
      debugPrint('[SemanticSearch] Error building cache: $e');
    }
  }

  /// Clear the embedding cache (call when entries change)
  void clearCache() {
    _embeddingCache.clear();
    _entryCache.clear();
    _cacheBuilt = false;
    debugPrint('[SemanticSearch] Cache cleared');
  }

  /// Invalidate a specific entry from cache
  void invalidateEntry(String entryId) {
    _embeddingCache.remove(entryId);
    _entryCache.remove(entryId);
  }

  /// Calculate cosine similarity between two vectors
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    final denominator = math.sqrt(normA) * math.sqrt(normB);
    if (denominator == 0) return 0.0;

    return dotProduct / denominator;
  }

  /// Merge keyword and semantic results
  List<SimpleSearchResult> _mergeResults(
    List<SimpleSearchResult> keywordResults,
    List<SimpleSearchResult> semanticResults, {
    double semanticWeight = 0.6,
  }) {
    final resultMap = <String, SimpleSearchResult>{};
    final scores = <String, double>{};

    // Add keyword results with normalized scores
    final maxKeywordScore = keywordResults.isEmpty
        ? 1.0
        : keywordResults.map((r) => r.matchCount).reduce(math.max).toDouble();

    for (final result in keywordResults) {
      final normalizedScore = result.matchCount / maxKeywordScore;
      final weightedScore = normalizedScore * (1 - semanticWeight);
      resultMap[result.id] = result;
      scores[result.id] = weightedScore;
    }

    // Add/merge semantic results
    for (final result in semanticResults) {
      final semanticScore = (result.similarityScore ?? 0) * semanticWeight;

      if (resultMap.containsKey(result.id)) {
        // Merge scores - boost items that match both
        scores[result.id] = (scores[result.id] ?? 0) + semanticScore + 0.1;
        // Keep the keyword result but add similarity score
        final existing = resultMap[result.id]!;
        resultMap[result.id] = SimpleSearchResult(
          id: existing.id,
          type: existing.type,
          title: existing.title,
          snippet: existing.snippet,
          fullContent: existing.fullContent,
          date: existing.date,
          matchCount: existing.matchCount,
          entryType: existing.entryType,
          similarityScore: result.similarityScore,
        );
      } else {
        resultMap[result.id] = result;
        scores[result.id] = semanticScore;
      }
    }

    // Sort by combined score
    final sortedIds = scores.keys.toList()
      ..sort((a, b) => (scores[b] ?? 0).compareTo(scores[a] ?? 0));

    return sortedIds.map((id) => resultMap[id]!).toList();
  }

  /// Extract a relevant snippet for semantic results
  String _extractSemanticSnippet(String content, String query) {
    // For semantic search, we don't have exact matches to highlight
    // Just return the beginning of the content
    const maxLength = 200;

    var snippet = content
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (snippet.length > maxLength) {
      snippet = '${snippet.substring(0, maxLength)}...';
    }

    return snippet;
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

/// Cached entry data
class _CachedEntry {
  final String title;
  final String content;
  final DateTime date;
  final String entryType;

  _CachedEntry({
    required this.title,
    required this.content,
    required this.date,
    required this.entryType,
  });
}
