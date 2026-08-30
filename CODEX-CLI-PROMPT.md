# Codex CLI implementation prompt

Work autonomously in this directory and finish NODAYSIDLE Voice from the existing native Swift scaffold. Build the actual low-interaction dictation product, not a dashboard mockup.

First read `AGENTS.md`, `PRD.md`, `ARD.md`, `TRD.md`, and `TASKS.md` completely. Treat them as the execution contract and follow their authority order. Inspect current source and tests before editing. Preserve user-owned changes.

Use the installed `brainstorming`, `swiftui-expert-skill`, and `frontend-polish` skills for UI work. Inspect the official Superwhisper recording-window documentation as an interaction reference before changing the shell: the proven hierarchy is hotkey-first dictation, a tiny optional floating capsule, waveform while recording, controls on hover, and explicit expansion to secondary UI. Do not copy Superwhisper assets, wording, dimensions, or styling. Before claiming visual completion, use the Product Design audit workflow against the running packaged app and inspect current screenshots. Use systematic debugging and test-driven development for every defect, and verification-before-completion before reporting success.

The common path is non-negotiable: press/hold the configurable global hotkey, speak, release, receive final text at the previous cursor, and dismiss the capsule automatically. The control center, history, and Settings must not open or take focus during this flow. The capsule is a borderless nonactivating AppKit panel that stays out of AeroSpork tiling/window cycling. Compact state shows only status or waveform; hover may reveal mode, stop/record, and expand. Escape cancels. Errors remain recoverable without losing recorded audio or completed text.

Implement phases in `TASKS.md` in order. Reuse the existing AppKit panel and SwiftUI shell; do not rebuild the project or introduce another UI framework. The app must remain native Swift/SwiftUI, original in design, BYOK, local-first, accessible, and memory-conscious. Do not replace the locked stack, add a backend/account system, or fake unavailable behavior. Remove scaffold-only behavior as each real feature lands.

Performance is a release gate: prove idle RSS <= 120 MiB without a loaded model, cloud recording RSS <= 200 MiB, Base local-model peak RSS <= 1.2 GiB, <= 50 MiB retained growth after a 30-minute record/cancel test, and one resident local model maximum. Use native controls, bounded audio, stable SwiftUI identity, throttled metering, and deterministic cleanup.

Run focused tests first, then `swift test`, `swift build -c release`, `Scripts/package_app.sh`, and strict code-sign verification. Perform a real TextEdit hotkey-to-insertion smoke, verify the previously focused app stays focused, and capture the compact/hover/recording/processing/error capsule states plus secondary control center and Settings. Do not install to `/Applications`, use API credentials, commit, push, or publish without explicit authorization.

Finish with an honest report separating source tests, packaged artifact, signing, installation, UI proof, memory proof, and live-provider proof. Use DONE only when every authorized gate passed; otherwise state PARTIAL or BLOCKED with the exact remaining evidence.
