# AGENTS.md — NODAYSIDLE Voice

## Authority order

1. `PRD.md` defines product behavior and acceptance.
2. `ARD.md` locks architecture, boundaries, privacy, and performance.
3. `TRD.md` defines concrete APIs, storage, UI, and commands.
4. `TASKS.md` defines executable phase order.
5. This file governs agent behavior.

Read all five before editing. Preserve existing user changes. Do not commit, push, deploy, install, or use credentials unless explicitly authorized.

## Locked stack

Native Swift 6.2, SwiftUI, focused AppKit/Carbon/Accessibility bridges, AVFoundation, Security/Keychain, SwiftData, URLSession, and WhisperKit/Core ML. Do not substitute Electron, Tauri, React, a webview, a remote backend, or an account system.

## Product constraints

- Match Superwhisper's proven interaction hierarchy, not its brand: hotkey-first dictation, tiny optional capsule, hover controls, and explicit secondary control center/history/settings. Keep NODAYSIDLE geometry, color, copy, assets, and code original.
- Do not turn the app into a dashboard or menu-popover-first product. Starting dictation must never open or focus the control center.
- Treat AeroSpork and SketchyBar as protected desktop defaults. Do not introduce AeroSpace, expose the native menu bar, edit the user's window-manager configuration, or use ordinary tileable windows for the compact panel/HUD.
- BYOK keys live only in Keychain and enter memory only for the active request.
- Local mode works offline after explicit model download.
- Never paste partial text or lose a completed transcript.
- Do not weaken privacy, correctness, accessibility, export, or performance gates to pass tests.
- Do not claim model download, transcription, hotkeys, insertion, or history works until it has real implementation and proof.

## Required skills

Before UI implementation or revision, use `brainstorming`, `swiftui-expert-skill`, and `frontend-polish`. Before final UI claims, use the Product Design audit workflow with current screenshots. Before bug fixes use systematic debugging and TDD. Before completion use verification-before-completion.

## Performance rules

- Prefer native controls and frameworks, bounded buffers, stable view identity, and one loaded local model.
- No polling loops, waveform history growth, duplicate audio buffers, unbounded transcript caches, or whole-view timer refresh.
- Every performance claim needs current measurement. Meet the PRD RSS and growth targets before declaring DONE.

## Completion

Run the exact verification commands in `TRD.md`, the focused tests for each phase, UI/accessibility review, memory measurement, packaged-app signature verification, and TextEdit end-to-end smoke. Report missing provider credentials as PARTIAL for live provider evidence only; do not search for or request keys.
