# NODAYSIDLE Voice — Product Requirements

## Product promise

NODAYSIDLE Voice is a fast, native macOS menu-bar dictation app. A user presses a configurable global hotkey, speaks, releases it, and receives accurate text at the previous cursor. The app supports private local transcription and explicit BYOK cloud transcription without a subscription backend.

The experience may learn from the clarity and speed of leading dictation apps, including Superwhisper, but the visual system, copy, interaction details, code, and assets must be original.

The default interaction is deliberately almost invisible: hold the push-to-talk shortcut, speak, release, and receive clean text at the prior cursor. A tiny floating capsule and sounds provide feedback; the control center, history, and Settings are secondary surfaces that never need to open during ordinary dictation.

## Users and outcomes

- A writer dictates messages, email, notes, and long-form text without changing apps.
- A developer dictates technical text while preserving names, punctuation, and code terms.
- A privacy-sensitive user downloads a local model once and works offline.
- A speed-focused user supplies a Deepgram or OpenRouter key and chooses cloud transcription.
- A power user creates reusable modes and application-specific defaults.

## Required workflows

### Dictate anywhere

1. Press or hold a configurable global hotkey.
2. Capture microphone audio and show a tiny floating capsule with a live waveform and state color. Stop/cancel controls appear only on hover or keyboard action.
3. Transcribe locally or through the explicitly selected cloud provider.
4. Optionally refine text with a separately selected OpenRouter text model.
5. Auto-paste, copy only, or preview before insertion.
6. Preserve existing clipboard contents where practical and never paste partial or failed output.

### Choose transcription

- Local: download, verify, select, load, unload, and remove WhisperKit/Core ML models.
- Deepgram BYOK: Nova-3 streaming for live microphone dictation.
- OpenRouter BYOK: dedicated speech-to-text endpoint for compatible transcription models.
- Local mode must remain fully usable after model download without network access.

### Modes

Ship Raw, Message, Email, Notes, Coding, Formal, and Casual. Users can add modes with an instruction, output language, transcription engine, refinement model, and insertion behavior. An optional per-application rule selects a default mode.

### History

Store completed transcript metadata and text locally. Search, copy, edit, re-paste, favorite, and delete. History can be disabled or cleared automatically. Audio is not retained unless the user explicitly chooses to save it.

### Settings

Provide General, Hotkeys, Providers, Local Models, Modes, Vocabulary, History, and Privacy sections. Keys are stored only in macOS Keychain. Permission recovery must link to the correct System Settings pane.

## Interaction hierarchy

1. **Hotkey-first:** the normal workflow is shortcut -> speak -> release -> text at cursor.
2. **Mini capsule:** the only default on-screen surface. Idle display is optional; recording shows a live waveform; processing shows a quiet progress state; success dismisses automatically.
3. **Hover controls:** mode, record/stop, and expand appear only while pointing at the capsule. Escape cancels. The recording shortcut also stops toggle-mode recording.
4. **Control center:** opened explicitly from the capsule context menu, SketchyBar launcher, URL scheme, or status item. It contains recent history, mode/engine selection, and Settings access.
5. **Settings and history:** ordinary native windows opened only when requested.

The app must not show a large menu popover when dictation begins, steal focus, or require clicking a microphone button for the common path.

## Quality requirements

- Original, premium native design with excellent light/dark appearance.
- Full keyboard navigation, VoiceOver labels, visible focus, reduced-motion behavior, and minimum 44-point primary targets where practical.
- Idle RSS without a loaded model: target <= 120 MiB.
- Cloud recording RSS: target <= 200 MiB.
- Load only one local transcription model at a time and unload it after configurable inactivity; Base-model local transcription target <= 1.2 GiB peak RSS.
- Thirty-minute record/cancel loop must not grow RSS by more than 50 MiB after returning idle.
- Mini capsule appears within 100 ms of the hotkey event; the secondary control center opens within 150 ms after warm launch.
- AeroSpork must not tile, resize, move, focus, or assign the control panel/HUD as ordinary app windows. The hidden native menu bar and visible SketchyBar workflow are first-class.
- No analytics, account system, mandatory backend, Electron, webview UI, or background daemon.

## Privacy and failure behavior

- Never store keys in defaults, files, logs, URLs, history, clipboard, or exported diagnostics.
- State plainly when audio or text will leave the Mac.
- Keep temporary audio only through the active request/retry window; delete and verify removal after success, discard, or expiry.
- On provider failure preserve the captured audio temporarily, offer retry/provider switch/local fallback, and keep prior transcripts intact.
- Model downloads require explicit user action, show source/size/progress, validate completion, and support deletion.

## Acceptance

The product succeeds when a clean install can complete permission setup, download or configure one engine, dictate into TextEdit from a global hotkey, obtain final text, insert it at the cursor, recover from a failed provider, find the result in local history, and remain within the memory targets above.
