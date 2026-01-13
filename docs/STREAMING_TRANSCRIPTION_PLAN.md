# Streaming Transcription Implementation Plan

> Addresses: #2 (Background transcription drops), #3 (Streaming transcription), #4 (UI improvements)
> Priority: Android first, quality over speed
> **Status: IMPLEMENTED** - January 8, 2026

## Overview

Parakeet TDT is **not a true streaming model** - it requires complete audio chunks. Our solution is **re-transcription streaming**: continuously re-transcribe a rolling window of audio to give real-time feedback while maintaining quality.

## Architecture

```
Audio (16kHz) → Noise Filter → VAD → SmartChunker
                                          │
                    ┌─────────────────────┴─────────────────────┐
                    │                                           │
                    ▼                                           ▼
           [Continuous Speech]                          [1s Silence Detected]
                    │                                           │
                    ▼                                           ▼
           Re-transcribe every 3s                       Finalize Chunk
           (rolling 15s window)                         (mark as confirmed)
                    │                                           │
                    ▼                                           ▼
           Stream interim text                          Persist to queue
           (grayed in UI)                               Save to journal
```

## Phase 1: Re-transcription Loop (Streaming Feedback)

### Changes to `live_transcription_service_v3.dart`

Add periodic re-transcription during active speech:

```dart
// New fields
Timer? _reTranscriptionTimer;
List<int> _rollingAudioBuffer = [];  // Last 15 seconds
String _interimText = '';
final _interimTextController = StreamController<String>.broadcast();

Stream<String> get interimTextStream => _interimTextController.stream;

// Start re-transcription loop when recording starts
void _startReTranscriptionLoop() {
  _reTranscriptionTimer = Timer.periodic(Duration(seconds: 3), (_) {
    if (_chunker?.stats.vadStats.isSpeaking ?? false) {
      _transcribeRollingBuffer();
    }
  });
}

// Transcribe last 15 seconds for interim display
Future<void> _transcribeRollingBuffer() async {
  if (_rollingAudioBuffer.isEmpty) return;

  // Take last 15 seconds (240,000 samples at 16kHz)
  const maxSamples = 16000 * 15;
  final audioToTranscribe = _rollingAudioBuffer.length > maxSamples
      ? _rollingAudioBuffer.sublist(_rollingAudioBuffer.length - maxSamples)
      : _rollingAudioBuffer;

  // Transcribe without queuing (fire and forget for UI)
  final result = await _transcriptionService.transcribeAudio(
    _samplesToTempWav(audioToTranscribe),
  );

  _interimText = result.text;
  _interimTextController.add(_interimText);
}
```

### Rolling Buffer Management

```dart
void _processAudioChunk(Uint8List audioBytes) {
  // ... existing processing ...

  // Add to rolling buffer (keep last 30s for overlap context)
  _rollingAudioBuffer.addAll(cleanSamples);
  const maxBufferSamples = 16000 * 30;
  if (_rollingAudioBuffer.length > maxBufferSamples) {
    _rollingAudioBuffer = _rollingAudioBuffer.sublist(
      _rollingAudioBuffer.length - maxBufferSamples
    );
  }
}
```

### Overlapping Context for Accuracy

When a chunk is finalized, keep last 5 seconds as "prefix" for next transcription:

```dart
void _handleChunk(List<int> samples) {
  // ... existing handling ...

  // Keep 5 second overlap in rolling buffer for context
  const overlapSamples = 16000 * 5;
  if (_rollingAudioBuffer.length > overlapSamples) {
    _rollingAudioBuffer = _rollingAudioBuffer.sublist(
      _rollingAudioBuffer.length - overlapSamples
    );
  }
}
```

## Phase 2: Persistent Transcription Queue (Background Recovery)

### Segment Persistence Model

Create `lib/features/recorder/models/persisted_segment.dart`:

```dart
class PersistedSegment {
  final int index;
  final String audioFilePath;
  final int startOffset;      // Byte offset in audio file
  final int durationSamples;  // Number of samples
  final SegmentStatus status;
  final String? transcribedText;
  final DateTime createdAt;
  final DateTime? completedAt;

  // JSON serialization for storage
  Map<String, dynamic> toJson() => {...};
  factory PersistedSegment.fromJson(Map<String, dynamic> json) => ...;
}

enum SegmentStatus {
  pending,
  processing,
  completed,
  failed,
  interrupted,  // Was processing when app closed
}
```

### Storage Service

Create `lib/features/recorder/services/segment_persistence_service.dart`:

```dart
class SegmentPersistenceService {
  static const _fileName = 'pending_segments.json';

  // Called when segment queued
  Future<void> saveSegment(PersistedSegment segment) async {
    final segments = await loadSegments();
    segments.add(segment);
    await _writeSegments(segments);
  }

  // Called on app launch
  Future<List<PersistedSegment>> loadPendingSegments() async {
    final segments = await loadSegments();
    // Mark any "processing" as "interrupted"
    return segments.where((s) =>
      s.status == SegmentStatus.pending ||
      s.status == SegmentStatus.interrupted
    ).toList();
  }

  // Called when transcription completes
  Future<void> markCompleted(int index, String text) async {...}

  // Called on journal save (cleanup old segments)
  Future<void> cleanup() async {...}
}
```

### Recovery Flow

In `main.dart` or recorder provider initialization:

```dart
Future<void> recoverPendingTranscriptions() async {
  final pendingSegments = await _persistenceService.loadPendingSegments();

  for (final segment in pendingSegments) {
    debugPrint('[Recovery] Resuming segment ${segment.index}');

    // Read audio from disk
    final audioFile = File(segment.audioFilePath);
    if (!await audioFile.exists()) {
      await _persistenceService.markFailed(segment.index, 'Audio file missing');
      continue;
    }

    // Extract segment audio using offset/duration
    final audioBytes = await audioFile.readAsBytes();
    final segmentAudio = audioBytes.sublist(
      segment.startOffset,
      segment.startOffset + (segment.durationSamples * 2),
    );

    // Queue for transcription
    _queueSegmentForProcessing(segmentAudio, segment.index);
  }
}
```

## Phase 3: UI Updates

### Recording Screen State

```dart
enum RecordingUIState {
  idle,           // Ready to record
  recording,      // Active recording
  processing,     // Post-record transcription
}

class TranscriptionDisplay {
  final List<String> confirmedSegments;
  final String? interimText;
  final bool isProcessing;
}
```

### Visual Hierarchy

```
┌──────────────────────────────────────────────────┐
│  Recording: 1:23                    [■ Stop]     │
├──────────────────────────────────────────────────┤
│                                                   │
│  I was thinking about the project today and      │  ← Confirmed (normal text)
│  realized we need to focus on quality.           │
│                                                   │
│  The streaming approach seems to work well       │  ← Interim (gray/italic)
│  for giving feedback while...▌                   │
│                                                   │
├──────────────────────────────────────────────────┤
│  ●●●●○ [VAD Level]                               │
└──────────────────────────────────────────────────┘
```

### Widget Structure

```dart
Widget build(BuildContext context) {
  return Column(
    children: [
      // Confirmed text (scrollable, selectable)
      Expanded(
        child: ListView.builder(
          itemCount: confirmedSegments.length,
          itemBuilder: (_, i) => Text(
            confirmedSegments[i],
            style: TextStyle(color: Colors.black),
          ),
        ),
      ),

      // Interim text (grayed, at bottom)
      if (interimText != null)
        Text(
          interimText,
          style: TextStyle(
            color: Colors.grey,
            fontStyle: FontStyle.italic,
          ),
        ),

      // VAD indicator
      VadLevelIndicator(level: vadLevel),
    ],
  );
}
```

## Parakeet-Specific: Final Word Flush

From richardtate research, Parakeet needs extra silence to flush internal buffers:

```dart
Future<String?> stopRecording() async {
  // ... existing stop logic ...

  // CRITICAL: Flush Parakeet's internal buffer with silence
  // This prevents the "lost last word" issue
  final silenceBuffer = List<int>.filled(16000 * 2, 0);  // 2 seconds
  _rollingAudioBuffer.addAll(silenceBuffer);

  // Force final transcription with silence padding
  await _transcribeRollingBuffer();

  // Then finalize
  _chunker?.flush();
  // ...
}
```

## Testing Matrix

### Background Recovery (#2)
- [ ] Force-close during transcription → relaunch → resumes
- [ ] Navigate away → navigate back → continues
- [ ] Background (Android) → return → continues
- [ ] Low memory kill → relaunch → resumes

### Streaming Quality (#3)
- [ ] Re-transcription updates every 3s during speech
- [ ] Interim text matches final after silence
- [ ] No duplicate text between chunks
- [ ] Final word captured (no truncation)

### UI Feedback (#4)
- [ ] Confirmed vs interim text visually distinct
- [ ] Smooth transitions on chunk finalization
- [ ] VAD indicator reflects speech detection
- [ ] Recording state clearly shown

## Implementation Order

1. **Week 1**: Phase 1 - Re-transcription loop
   - Add rolling buffer
   - Periodic transcription during speech
   - Interim text stream
   - Test on Android

2. **Week 2**: Phase 2 - Persistence
   - Segment storage model
   - Save/load pending segments
   - Recovery on launch
   - Test interruption scenarios

3. **Week 3**: Phase 3 - UI
   - Recording takeover UI
   - Confirmed vs interim styling
   - VAD indicator
   - Polish transitions

## References

- [richardtate implementation](https://github.com/lucianhymer/richardtate) - VAD chunking source
- [sherpa-onnx #2918](https://github.com/k2-fsa/sherpa-onnx/issues/2918) - Parakeet streaming limitations
- [Meetily/meeting-minutes](https://github.com/Zackriya-Solutions/meeting-minutes) - Production reference
