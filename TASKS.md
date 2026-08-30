# NODAYSIDLE Voice — Implementation Tasks

Execute phases in order. A later phase may modify files created by an earlier phase; it must not claim unavailable behavior.

## Phase 0 — Align the shell with the product interaction

- Run `swift test` and `swift build`.
- Inspect the mini capsule, explicit control center, Settings navigation, Keychain save/remove flow, light mode, dark mode, keyboard navigation, and VoiceOver labels.
- Prove `Scripts/toggle.sh` opens and closes the same fixed panel while preserving the currently focused application under AeroSpork/SketchyBar.
- Prove starting dictation shows only the capsule and never opens or activates the control center.
- Implement compact, hover-expanded, recording, processing, success, and error capsule states. The compact state must contain no provider/settings/history copy.
- Replace scaffold-only copy when implementing its feature; never leave a control that pretends an operation succeeded.
- Acceptance: clean build and screenshots of the primary surfaces at standard and increased text sizes.

## Phase 1 — Recording state and microphone capture

- Create `Services/AudioCaptureService.swift` and focused tests.
- Add microphone authorization and guided recovery.
- Implement bounded PCM capture, temporary file, level metering <= 20 Hz, cancel, and deterministic cleanup.
- Connect real state to the capsule; replace the illustrative waveform with bounded live levels.
- Acceptance: record/cancel 100 times without leaked taps, files, or >50 MiB post-idle RSS growth.

## Phase 2 — Global hotkeys and insertion

- Create `Services/HotkeyController.swift`, `Services/InsertionService.swift`, and permission coordinator.
- Implement configurable push-to-talk and toggle hotkeys with conflict detection.
- Capture the prior app and cursor workflow; implement auto-paste, copy-only, preview-first, and guarded clipboard restoration.
- Acceptance: dictate simulated final text into TextEdit, Notes, Safari, and a terminal; incomplete text is never pasted.

## Phase 3 — Local transcription and model downloads

- Pin WhisperKit and implement `LocalWhisperEngine` plus `LocalModelManager`.
- Replace the scaffold model buttons with real download/progress/verify/activate/remove behavior.
- Enforce one loaded model and five-minute unload; respond to memory pressure.
- Acceptance: install Base, go offline, transcribe, remove it, and prove idle/local memory targets.

## Phase 4 — BYOK cloud transcription

- Implement Deepgram Nova-3 streaming for live microphone audio.
- Implement OpenRouter STT for buffered microphone audio and imported files.
- Load credentials from Keychain only at request time; add connection tests that never reveal keys.
- Add timeout, cancel, rate-limit, retry, switch-provider, usage, and cleanup behavior.
- Acceptance: one authenticated canary per provider, plus mocked failure tests. If no user key is supplied, report live proof as PARTIAL without seeking credentials.

## Phase 5 — Modes and optional refinement

- Add built-in and custom mode persistence, vocabulary, and per-app rules.
- Add explicit import for the private Superwhisper migration file and verify 288 vocabulary hints plus 264 replacements without bundling or committing it.
- Implement optional OpenRouter refinement independently of transcription.
- Keep raw transcript when refinement fails; Raw mode makes no refinement request.
- Acceptance: deterministic fixtures prove instruction fidelity and no cross-mode leakage.

## Phase 6 — History and file transcription

- Add SwiftData history with search, copy, edit, re-paste, favorite, delete, disable, and retention.
- Add file import for provider-supported audio formats with explicit routing and bounded preflight.
- Acceptance: persistence migration test, retention test, and no-audio-retained-by-default proof.

## Phase 7 — UX, accessibility, and performance gate

- Use `swiftui-expert-skill`, `frontend-polish`, and the Product Design audit workflow.
- Capture and inspect screenshots for onboarding, ready, recording, transcribing, success, permission denial, offline, rate limit, model download, provider error, and empty history.
- Compare the running app's interaction hierarchy against the official Superwhisper recording-window reference, while rejecting copied assets, wording, or pixel imitation.
- Run Accessibility Inspector and keyboard-only flow.
- Measure launch, popover open, idle RSS, cloud recording RSS, local Base peak RSS, CPU, energy, and 30-minute growth.
- Fix measured problems; do not add decorative animation or abstraction without evidence.

## Phase 8 — Package and verify

- Package, sign, and run the exact built app.
- Verify bundle ID, microphone usage string, Keychain behavior, icon, strict signature, launch, and absence of fixture/debug markers.
- Install to `/Applications/NODAYSIDLE Voice.app` only after explicit user authorization.
- Report build, tests, packaged artifact, signing, installation, runtime smoke, memory evidence, and live provider evidence as separate gates.
