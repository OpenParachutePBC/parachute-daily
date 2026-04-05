import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute/core/models/thing.dart';
import 'package:parachute/core/screens/note_detail_screen.dart';
import 'package:parachute/core/theme/design_tokens.dart';
import '../providers/vault_providers.dart';

/// Vault tab — search, browse tags, and explore all notes.
class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    ref.read(vaultSearchQueryProvider.notifier).state = query;
  }

  void _selectTag(String? tag) {
    ref.read(vaultTagFilterProvider.notifier).state = tag;
  }

  void _refresh() {
    ref.read(vaultRefreshTriggerProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final searchQuery = ref.watch(vaultSearchQueryProvider);
    final isSearching = searchQuery.trim().isNotEmpty;
    final activeTag = ref.watch(vaultTagFilterProvider);

    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row
                Row(
                  children: [
                    Expanded(
                      child: Text('Vault', style: theme.textTheme.headlineSmall),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Search bar
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search notes...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.sm),
                      borderSide: BorderSide(
                        color: (isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood)
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    isDense: true,
                  ),
                  onChanged: _onSearchChanged,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Divider(height: 1),
        // Content
        Expanded(
          child: isSearching ? _buildSearchResults() : _buildBrowseView(activeTag),
        ),
      ],
    );
  }

  Widget _buildSearchResults() {
    final resultsAsync = ref.watch(vaultSearchProvider);

    return resultsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (results) {
        if (results == null || results.isEmpty) {
          return Center(
            child: Text(
              results == null ? '' : 'No results found',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          );
        }
        return _buildNotesList(results);
      },
    );
  }

  Widget _buildBrowseView(String? activeTag) {
    return Column(
      children: [
        // Tag chips
        _buildTagBar(activeTag),
        // Notes list
        Expanded(
          child: _buildFilteredNotes(),
        ),
      ],
    );
  }

  Widget _buildTagBar(String? activeTag) {
    final tagsAsync = ref.watch(vaultTagsProvider);

    return tagsAsync.when(
      loading: () => const SizedBox(height: 48),
      error: (_, __) => const SizedBox(height: 48),
      data: (tags) {
        if (tags.isEmpty) return const SizedBox.shrink();

        final isDark = Theme.of(context).brightness == Brightness.dark;
        // Filter out system tags from the chip bar
        final displayTags = tags.where((t) =>
            t.tag != 'view' && t.tag != 'pinned' && t.tag != 'archived'
        ).toList();

        return SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              // "All" chip
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: const Text('All'),
                  selected: activeTag == null,
                  onSelected: (_) => _selectTag(null),
                  visualDensity: VisualDensity.compact,
                  selectedColor: (isDark ? BrandColors.nightTurquoise : BrandColors.turquoise)
                      .withValues(alpha: 0.2),
                ),
              ),
              ...displayTags.map((tag) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text('${tag.tag} (${tag.count})'),
                      selected: activeTag == tag.tag,
                      onSelected: (_) => _selectTag(
                        activeTag == tag.tag ? null : tag.tag,
                      ),
                      visualDensity: VisualDensity.compact,
                      selectedColor: (isDark ? BrandColors.nightTurquoise : BrandColors.turquoise)
                          .withValues(alpha: 0.2),
                    ),
                  )),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilteredNotes() {
    final notesAsync = ref.watch(vaultNotesProvider);

    return notesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (notes) {
        if (notes.isEmpty) {
          return _buildEmpty();
        }
        return RefreshIndicator(
          onRefresh: () async {
            _refresh();
            await ref.read(vaultNotesProvider.future);
          },
          child: _buildNotesList(notes),
        );
      },
    );
  }

  Widget _buildNotesList(List<Note> notes) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: notes.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
      itemBuilder: (context, index) => _VaultNoteItem(
        note: notes[index],
        onChanged: _refresh,
      ),
    );
  }

  Widget _buildEmpty() {
    final theme = Theme.of(context);
    final activeTag = ref.read(vaultTagFilterProvider);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              activeTag != null ? 'No #$activeTag notes' : 'Vault is empty',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              activeTag != null
                  ? 'No notes with this tag yet.'
                  : 'Notes will appear here as you capture and create.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }
}

class _VaultNoteItem extends StatelessWidget {
  final Note note;
  final VoidCallback onChanged;

  const _VaultNoteItem({required this.note, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final title = note.path ?? '';
    final preview = note.content.length > 120
        ? '${note.content.substring(0, 120)}...'
        : note.content;
    final date = note.updatedAt ?? note.createdAt;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      title: Row(
        children: [
          Expanded(
            child: Text(
              title.isNotEmpty ? title : preview,
              maxLines: title.isNotEmpty ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: title.isNotEmpty ? theme.textTheme.titleMedium : null,
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 2,
            children: note.tags
                .where((t) => t != 'pinned' && t != 'archived')
                .map((t) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: BrandColors.forest.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        '#$t',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: BrandColors.forest,
                          fontSize: 10,
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
      trailing: Text(
        _shortDate(date),
        style: theme.textTheme.bodySmall?.copyWith(
          color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
        ),
      ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => NoteDetailScreen(
              note: note,
              onChanged: onChanged,
            ),
          ),
        );
      },
    );
  }

  static String _shortDate(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}
