# Daily

Voice journaling app. Runs standalone (no server required).

**Repository**: https://github.com/OpenParachutePBC/parachute-daily

---

## Architecture

```
UI (Screens) → Providers (Riverpod) → Services → Local Storage
                     ↓                    ↓
              Local ML Models    ~/Parachute/Daily/
              (Parakeet, EmbeddingGemma)
```

**Key pieces:**
- `lib/features/journal/services/journal_service.dart` - Journal CRUD
- `lib/features/recorder/services/audio_service.dart` - Audio recording
- `lib/features/recorder/services/live_transcription_service_v3.dart` - Real-time transcription
- `lib/core/services/embedding/` - Semantic search embeddings

**Vault paths:**
- `Daily/journals/YYYY/MM/DD.md` - Journal entries (markdown)
- `assets/YYYY-MM/` - Audio files

---

## Daily-specific patterns

### Para-ID system
Journal entries use portable IDs for cross-device sync:
```markdown
## para:abc123xyz 10:30 AM

Voice transcription text...

[Audio: 2025-12-30_10-30-00.opus]
```

### Platform-adaptive services
```dart
final embeddingServiceProvider = Provider<EmbeddingService>((ref) {
  if (Platform.isAndroid || Platform.isIOS) {
    return ref.watch(mobileEmbeddingServiceProvider);  // flutter_gemma
  } else {
    return ref.watch(desktopEmbeddingServiceProvider); // Ollama
  }
});
```

| Feature | Desktop | Mobile |
|---------|---------|--------|
| Transcription | FluidAudio (CoreML) | Sherpa-ONNX |
| Embeddings | Ollama | flutter_gemma |

### Optimistic UI with refresh triggers
```dart
// After mutation, trigger refresh for other providers
void _triggerRefresh() {
  _ref.read(journalRefreshTriggerProvider.notifier).state++;
}
```

---

## Conventions

### Provider types (same as Chat)

| Type | Use for | Example |
|------|---------|---------|
| `Provider<T>` | Singleton services | `audioServiceProvider` |
| `FutureProvider<T>` | Async initialization | `journalServiceFutureProvider` |
| `StateNotifierProvider` | Mutable state with methods | `transcriptionProgressProvider` |
| `StreamProvider` | Reactive streams | `streamingTranscriptionProvider` |
| `StreamProvider.autoDispose` | Auto-cleanup streams | `vadActivityProvider` |
| `StateProvider` | Simple UI state | `selectedJournalDateProvider` |

### Service patterns

```dart
// Factory with async init
class JournalService {
  JournalService._({required this.vaultPath});

  static Future<JournalService> create({
    required FileSystemService fileSystemService,
  }) async {
    final vaultPath = await fileSystemService.getRootPath();
    return JournalService._(vaultPath: vaultPath);
  }
}

// Thread-safe initialization guard
Completer<void>? _initCompleter;
Future<void> ensureInitialized() async {
  if (_isInitialized) return;
  if (_initCompleter != null) {
    await _initCompleter!.future;
    return;
  }
  await initialize();
}
```

### Debug logging
```dart
debugPrint('[ClassName] message');
```

---

## Gotchas

- Models download on first use via Settings → Local AI Models (~500MB for transcription)
- Omi pendant integration is behind a feature flag
- VAD (voice activity detection) auto-pauses recording during silence
- Embeddings use 256 dimensions (Matryoshka truncation from 768) for efficiency
- The recorder feature has multiple provider files due to complexity (audio, transcription, Omi, VAD)
