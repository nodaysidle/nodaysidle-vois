# NODAYSIDLE Voice — Architecture Requirements

## Locked architecture

- Swift 6.2, SwiftUI, and focused AppKit bridges.
- Swift Package Manager; native `.app` packaging without an Xcode project is supported.
- AppKit `NSStatusItem` plus fixed-size non-activating `NSPanel` surfaces hosting SwiftUI. The primary surface is a small floating capsule; the larger control center is secondary. Do not use `MenuBarExtra`: the native menu bar is hidden on the target Mac and SketchyBar is the visible entry point.
- AVFoundation for microphone capture and level metering.
- Carbon hotkey registration or an equally native audited mechanism; no accessibility-event tap merely to detect shortcuts.
- Accessibility API and pasteboard for insertion, with explicit permission handling and clipboard restoration.
- Security framework for Keychain secrets.
- SwiftData for settings, modes, vocabulary, and transcript history; audio files remain outside the database.
- WhisperKit/Core ML for downloadable local transcription.
- URLSession WebSocket for Deepgram Nova-3 streaming.
- URLSession HTTP for OpenRouter transcription and optional text refinement.

## Runtime boundaries

`AppCoordinator` owns lifecycle and connects these focused services:

- `HotkeyController`: register, detect conflicts, and deliver push-to-talk/toggle events.
- `AudioCaptureService`: one AVAudioEngine, PCM conversion, metering, temporary-file lifecycle.
- `TranscriptionRouter`: select exactly one transcription engine per job.
- `LocalWhisperEngine`: model download/load/transcribe/unload.
- `DeepgramEngine`: live microphone WebSocket only.
- `OpenRouterSTTEngine`: completed buffered audio/file transcription through `/api/v1/audio/transcriptions`.
- `RefinementService`: optional transcript-to-text operation; never receives audio.
- `InsertionService`: capture target app, paste/copy/preview, restore clipboard where safe.
- `HistoryStore`: local completed results and metadata.
- `CredentialStore`: Keychain only.
- `PermissionCoordinator`: microphone, Accessibility, Input Monitoring when demonstrably required.

No engine may write UI state directly. Every dictation job uses one explicit state machine:

`idle -> arming -> recording -> transcribing -> refining? -> inserting? -> completed`

Every non-idle state can reach `cancelled` or `failed`, and cleanup runs on every terminal path.

## Memory discipline

- Keep audio streaming/buffered in bounded chunks; never retain duplicate full recordings in memory.
- Keep one AVAudioEngine instance and tear down taps deterministically.
- Permit only one resident local model. Release the pipeline after the inactivity timeout or memory pressure.
- Use actors for audio job ownership and model lifecycle; UI state remains `@MainActor @Observable`.
- History lists fetch lightweight rows and load full transcript text only when opened.
- Do not cache waveform samples, model catalogs, or transcript copies without a measured need.

## UI architecture

- One observable application model with narrow feature models when state ownership demands it.
- Small SwiftUI views with stable identities; no `AnyView`, timer-driven whole-tree refresh, or geometry polling.
- AppKit bridges are isolated behind small concrete types, not speculative protocol forests.
- Original visual tokens: NODAYSIDLE coral accent, neutral materials, strong type hierarchy, restrained motion.
- One shared `togglePanel()` path serves the status item, `nodaysidlevoice://toggle`, and the SketchyBar launcher. Panels use floating level, fixed content size, all-space/full-screen auxiliary behavior, no focus theft, and no saved desktop position.
- `MiniCapsuleController` owns one nonactivating, borderless panel near the bottom center of the active display. Its compact state contains only status/waveform; hover may reveal mode, stop/record, and expand without activating the app.
- The capsule auto-hides after successful insertion and may be disabled entirely. Errors remain visible until dismissed or retried. Right-click exposes Control Center, History, Settings, and Quit.
- The control center must never open as a side effect of starting, stopping, transcribing, or inserting a dictation.

## Security boundaries

- Keychain service: `com.nodaysidle.voice`; distinct accounts per provider.
- Provider request builders accept a credential only at send time and never place it in persisted request models.
- Logs contain allowlisted metadata only: engine, duration bucket, status class, and anonymous request ID when supplied.
- Local model manifests include immutable source identity and validated artifact state before activation.

## Packaging

- Bundle ID: `com.nodaysidle.voice`.
- `LSUIElement=true`; Settings and HUD still activate correctly.
- Required microphone usage string and minimal entitlements.
- Development: ad-hoc signing. Distribution: Developer ID, hardened runtime, notarization, and stapling.
