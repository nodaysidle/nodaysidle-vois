<div align="center">
  <img src="Assets/AppIcon.png" width="144" alt="NODAYSIDLE Voice app icon">
  <h1>NODAYSIDLE Voice</h1>
  <p><strong>Native, hotkey-first dictation for macOS.</strong></p>
  <p>Speak from anywhere. Keep transcription local, or bring your own cloud provider.</p>

  <p>
    <img src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple" alt="macOS 14 or later">
    <img src="https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white" alt="Swift 6.2">
    <img src="https://img.shields.io/badge/native-SwiftUI-0A84FF" alt="Native SwiftUI">
    <a href="https://github.com/nodaysidle/nodaysidle-vois/releases/latest"><img src="https://img.shields.io/github/v/release/nodaysidle/nodaysidle-vois?display_name=tag" alt="Latest release"></a>
  </p>
</div>

<table>
  <tr>
    <td width="54%" align="center"><img src="Artifacts/UI-Audit/01-control-center-dark.png" alt="NODAYSIDLE Voice control center"></td>
    <td width="46%" align="center"><img src="Artifacts/UI-Audit/09-capsule-recording-dark.png" alt="Compact recording capsule and modes"></td>
  </tr>
</table>

NODAYSIDLE Voice is a native macOS menu-bar app built around one fast interaction: hold a shortcut, speak, release, and place only the completed transcript at the previous cursor. Starting dictation never opens the control center or steals focus with a normal window.

## Download

[**Download NODAYSIDLE Voice v0.1.0**](https://github.com/nodaysidle/nodaysidle-vois/releases/download/v0.1.0/NODAYSIDLE-Voice-0.1.0.dmg)

Requirements: macOS 14 Sonoma or later on Apple silicon.

1. Open the DMG and drag **NODAYSIDLE Voice** to **Applications**.
2. The current release is ad-hoc signed and not Apple-notarized. On first launch, Control-click the app, choose **Open**, then confirm **Open**.
3. Grant microphone access. Grant Accessibility access only when you want automatic insertion into other apps.
4. Download a local Whisper model, or save your own provider key in Settings.

No model or API credential is bundled with the app.

## Why it feels fast

- Global push-to-talk and toggle shortcuts backed by Carbon hotkeys
- Tiny optional capsule with bounded live levels and hover controls
- Final-text-only insertion—partial speech is never pasted
- Per-app modes for raw text, messages, notes, email, coding, and formal writing
- Searchable local history, vocabulary, replacements, and audio-file transcription
- Native SwiftUI/AppKit surfaces that remain outside ordinary window tiling

## Shortcuts

| Action | Default |
| --- | --- |
| Hold to dictate | `⌃ Space` |
| Toggle dictation | `⇧ ⌥ Space` |
| Cancel an active job | `Escape` |

Shortcuts can be changed in Settings.

## Transcription engines

| Engine | Best for | Data boundary |
| --- | --- | --- |
| WhisperKit | Offline, local-first dictation | Audio stays on this Mac after an explicit model download |
| Deepgram Nova-3 | Low-latency streaming | Active-request audio is sent directly to Deepgram using your Keychain-stored key |
| OpenRouter STT | Batch transcription and optional refinement | Active-request audio/text is sent directly to OpenRouter using your Keychain-stored key |

Only one local model is kept resident at a time, and it can be unloaded when idle.

## Privacy

- Provider keys live only in macOS Keychain.
- Temporary microphone audio is owned by the active request and removed after success or discard.
- Completed transcript history stays locally in SwiftData and stores no audio.
- Cloud transfer is explicit in the selected engine and limited to the active operation.
- `UserData/` is private, ignored by Git, and imported only through an explicit file choice.

## Verified compatibility

The completed-text insertion path has GUI smoke coverage in:

- Microsoft Edge
- ChatGPT for macOS
- Ghostty
- TextEdit

The automated smokes insert unique markers without submitting messages, navigating, or executing shell commands.

## Build from source

Install Xcode Command Line Tools with Swift 6.2, then run:

```bash
swift test
swift build -c release
./Scripts/package_app.sh
open "NODAYSIDLE Voice.app"
```

Create the same distributable DMG used by GitHub Releases:

```bash
./Scripts/package_dmg.sh
```

Artifacts are written to `dist/` with a matching `SHA256SUMS.txt`.

## Project structure

- `Sources/NODAYSIDLEVoice/` — app lifecycle, UI, audio, providers, insertion, and persistence
- `Tests/NODAYSIDLEVoiceTests/` — focused unit, storage, provider-boundary, audio, and GUI-smoke coverage
- `Assets/` — original application and menu-bar artwork
- `Scripts/` — deterministic app and DMG packaging
- `PRD.md`, `ARD.md`, `TRD.md`, `TASKS.md` — product and implementation contracts

## Release status

Version `0.1.0` is an early public release. The app is ad-hoc signed rather than Developer ID signed/notarized, local models are downloaded separately, and cloud engines require your own provider credentials.

---

<div align="center">
  Built by <a href="https://github.com/nodaysidle">NODAYSIDLE</a>.
</div>
