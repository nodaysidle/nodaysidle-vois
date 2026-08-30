# NODAYSIDLE Voice — Technical Requirements

## Project structure

```text
Sources/NODAYSIDLEVoice/
  NODAYSIDLEVoiceApp.swift
  AppModel.swift
  Models/
  Views/
  Services/
Tests/NODAYSIDLEVoiceTests/
Scripts/package_app.sh
```

Extend the existing scaffold; do not replace it with Electron, Tauri, a web frontend, or an Xcode-only layout.

## Provider contracts

### Deepgram

- Connect to `wss://api.deepgram.com/v1/listen` with `model=nova-3`, explicit encoding/sample rate/channels, interim results, smart formatting, endpointing, and finalization.
- Send microphone PCM frames only. Imported audio files do not use this live stream.
- Treat only final results as insertable. KeepAlive, Finalize, CloseStream, cancellation, timeout, and provider-error paths must be tested.

### OpenRouter STT

- `POST https://openrouter.ai/api/v1/audio/transcriptions`.
- JSON request contains selected model and base64 `input_audio { data, format }` as documented by OpenRouter.
- Discover transcription models using the transcription output-modality catalog; cache metadata briefly, not credentials.
- Validate supported format and bounded payload before encoding. Parse `text` and optional usage/cost.

### OpenRouter refinement

- Use the documented chat-completions contract with the selected text model.
- Input contains completed transcript and the active mode instruction only.
- Disable reasoning when the selected model supports it; use temperature 0 for deterministic cleanup where accepted.
- Refinement failure returns the raw completed transcript and must not lose it.

## Local models

- Add WhisperKit as a pinned SwiftPM dependency after the scaffold build remains green.
- The model manager exposes catalog, disk size, installed state, download progress, active model, remove, and retry.
- Default recommendation is a small model appropriate to hardware; never auto-download multiple models.
- Download to a temporary location, validate the complete WhisperKit model directory, then atomically promote into Application Support.
- Local transcription performs no network call after installation.
- Unload the active model after five idle minutes by default and immediately under memory pressure.

## Audio and insertion

- Capture mono PCM through AVAudioEngine with a bounded buffer and meter updates throttled to <= 20 Hz.
- Record one temporary audio file per job; delete it on success/discard/expiry.
- Capture the frontmost target application before showing UI.
- In auto-paste mode, place final text on NSPasteboard, issue the paste command through Accessibility, then restore the prior pasteboard only if its change count proves no third-party overwrite occurred.
- Copy-only never sends synthetic input. Preview-first requires explicit confirmation.

## Persistence

- SwiftData entities: `TranscriptRecord`, `ModeRecord`, `VocabularyEntry`, and `AppRule`.
- UserDefaults stores only non-sensitive scalar preferences such as insertion mode and inactivity timeout.
- Keychain stores Deepgram and OpenRouter keys.
- Transcript history excludes audio by default and supports retention cleanup at launch and once per day.

## UI requirements

- Mini capsule: the primary surface, approximately 120-160 pt wide at rest and no taller than 48 pt. During recording it shows a live waveform and state color. Hover expansion may reveal mode, stop/record, and expand controls; Escape cancels. No title, settings list, transcript history, provider name, or explanatory copy belongs in the compact state.
- Control center: secondary fixed panel with record control, current mode/engine, recent items, status, and Settings. It opens only from an explicit launcher or capsule action.
- Settings: General, Hotkeys, Providers, Local Models, Modes, Vocabulary, History, Privacy.
- Every async screen has empty, loading, success, offline, permission, rate-limit, and provider-error states.
- Use native materials, controls, typography, focus, and accessibility. Avoid excessive blur, continuous animation, custom control replicas, and large in-memory images.
- Default presentation is dark, compact, and optional. The user can disable the HUD and rely on start/finish/error sounds.
- SketchyBar calls `Scripts/toggle.sh`; the URL handler must toggle the same fixed panel without activating or changing the focused target application.
- Window behavior under AeroSpork: borderless nonactivating panels, fixed size, floating level, all Spaces, fullscreen auxiliary, excluded from Window menu/cycle, never tiled, never position-restored, and never made key during the hotkey workflow.
- Visual reference boundary: match Superwhisper's low-interaction hierarchy (mini idle/recording capsule, hover controls, optional expansion), but use original NODAYSIDLE geometry, coral state color, symbols, copy, and code. Do not copy screenshots or assets.

## Dictionary migration

- A private local migration file exists at `UserData/superwhisper-dictionary.json`; it is mode `0600` and git-ignored.
- It contains only the user's 288 vocabulary hints and 264 deterministic replacements. Never bundle or commit this user-specific file.
- Import vocabulary into SwiftData on explicit user action. Apply replacements locally, case-insensitively, after raw transcription and before optional LLM refinement. Preserve replacement output casing exactly.
- Deduplicate entries, show conflicts before import, and retain the source file until imported counts are verified.

## Verification commands

```bash
swift test
swift build -c release
Scripts/package_app.sh
codesign --verify --deep --strict "NODAYSIDLE Voice.app"
```

Use Instruments/`footprint` evidence for the PRD memory targets, an Accessibility Inspector pass, and a real TextEdit dictation smoke before claiming complete.
