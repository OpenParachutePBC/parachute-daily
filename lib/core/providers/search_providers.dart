import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_daily/core/providers/embedding_provider.dart';
import 'package:parachute_daily/core/services/search/simple_text_search.dart';
import 'package:parachute_daily/core/services/search/semantic_search_service.dart';
import 'package:parachute_daily/features/journal/providers/journal_providers.dart';

/// Provider for the simple text search service
/// Uses AsyncValue since JournalService requires async initialization
final simpleTextSearchProvider = FutureProvider<SimpleTextSearchService>((ref) async {
  final journalService = await ref.watch(journalServiceFutureProvider.future);
  return SimpleTextSearchService(journalService: journalService);
});

/// Provider for the semantic search service (hybrid keyword + semantic)
final semanticSearchProvider = FutureProvider<SemanticSearchService>((ref) async {
  final journalService = await ref.watch(journalServiceFutureProvider.future);
  final embeddingService = ref.watch(embeddingServiceProvider);
  final keywordSearch = await ref.watch(simpleTextSearchProvider.future);

  return SemanticSearchService(
    embeddingService: embeddingService,
    journalService: journalService,
    keywordSearch: keywordSearch,
  );
});

/// Search mode
enum SearchMode {
  /// Keyword-only search (fastest, no model required)
  keyword,

  /// Hybrid search (keyword + semantic when available)
  hybrid,

  /// Semantic-only search (requires embedding model)
  semantic,
}

/// State for search results
class SearchState {
  final String query;
  final List<SimpleSearchResult> results;
  final bool isLoading;
  final String? error;
  final bool isInitialized;
  final SearchMode mode;
  final bool semanticAvailable;

  const SearchState({
    this.query = '',
    this.results = const [],
    this.isLoading = false,
    this.error,
    this.isInitialized = false,
    this.mode = SearchMode.hybrid,
    this.semanticAvailable = false,
  });

  SearchState copyWith({
    String? query,
    List<SimpleSearchResult>? results,
    bool? isLoading,
    String? error,
    bool? isInitialized,
    SearchMode? mode,
    bool? semanticAvailable,
  }) {
    return SearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isInitialized: isInitialized ?? this.isInitialized,
      mode: mode ?? this.mode,
      semanticAvailable: semanticAvailable ?? this.semanticAvailable,
    );
  }
}

/// Notifier for managing search state
class SearchNotifier extends StateNotifier<SearchState> {
  final Ref _ref;

  SearchNotifier(this._ref) : super(const SearchState()) {
    // Check semantic availability on init
    _checkSemanticAvailability();
  }

  /// Check if semantic search is available
  Future<void> _checkSemanticAvailability() async {
    try {
      final semanticService = _ref.read(semanticSearchProvider).valueOrNull;
      if (semanticService != null) {
        final available = await semanticService.isAvailable();
        state = state.copyWith(semanticAvailable: available);
      }
    } catch (e) {
      // Semantic not available
    }
  }

  /// Set search mode
  void setMode(SearchMode mode) {
    state = state.copyWith(mode: mode);
    // Re-run search if there's a query
    if (state.query.isNotEmpty) {
      search(state.query);
    }
  }

  /// Perform a search with the given query
  Future<void> search(String query) async {
    if (query.trim().isEmpty) {
      state = state.copyWith(query: '', results: [], isLoading: false);
      return;
    }

    state = state.copyWith(query: query, isLoading: true, error: null);

    try {
      List<SimpleSearchResult> results;

      if (state.mode == SearchMode.keyword) {
        // Keyword-only search
        final keywordService = _ref.read(simpleTextSearchProvider).valueOrNull;
        if (keywordService == null) {
          state = state.copyWith(isLoading: false, error: 'Search service not ready');
          return;
        }
        results = await keywordService.search(query);
      } else {
        // Hybrid or semantic search
        final semanticService = _ref.read(semanticSearchProvider).valueOrNull;
        if (semanticService == null) {
          // Fallback to keyword search
          final keywordService = _ref.read(simpleTextSearchProvider).valueOrNull;
          if (keywordService == null) {
            state = state.copyWith(isLoading: false, error: 'Search service not ready');
            return;
          }
          results = await keywordService.search(query);
        } else {
          results = await semanticService.search(
            query,
            semanticOnly: state.mode == SearchMode.semantic,
          );

          // Update semantic availability
          final available = await semanticService.isAvailable();
          state = state.copyWith(semanticAvailable: available);
        }
      }

      state = state.copyWith(results: results, isLoading: false, isInitialized: true);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Search failed: $e',
      );
    }
  }

  /// Clear search results
  void clear() {
    state = state.copyWith(query: '', results: [], isLoading: false);
  }
}

/// Provider for search state
final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  return SearchNotifier(ref);
});
