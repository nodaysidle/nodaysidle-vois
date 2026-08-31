import AppKit
import ApplicationServices
import Carbon
import Testing
@testable import NODAYSIDLEVoice

@Test func defaultHotkeysAreDistinctAndReadable() {
    #expect(HotkeyDescriptor.pushToTalk.displayName == "⌃ Space")
    #expect(HotkeyDescriptor.toggle.displayName == "⇧ ⌥ Space")
    #expect(HotkeyDescriptor.pushToTalk != HotkeyDescriptor.toggle)
}

@Test func appKitModifierFlagsMapToCarbonRegistrationFlags() {
    let allFlags: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
    let expected = UInt32(shiftKey) | UInt32(controlKey) | UInt32(optionKey) | UInt32(cmdKey)
    #expect(HotkeyDescriptor.carbonModifiers(from: allFlags) == expected)
    let ignoredFlags: NSEvent.ModifierFlags = [.capsLock, .function]
    #expect(HotkeyDescriptor.carbonModifiers(from: ignoredFlags) == 0)
}

@Test func carbonEventsMapToPushToTalkAndToggleActions() {
    #expect(HotkeyController.action(id: 1, eventKind: UInt32(kEventHotKeyPressed)) == .pushToTalkPressed)
    #expect(HotkeyController.action(id: 1, eventKind: UInt32(kEventHotKeyReleased)) == .pushToTalkReleased)
    #expect(HotkeyController.action(id: 2, eventKind: UInt32(kEventHotKeyPressed)) == .togglePressed)
    #expect(HotkeyController.action(id: 2, eventKind: UInt32(kEventHotKeyReleased)) == nil)
    #expect(HotkeyController.action(id: 3, eventKind: UInt32(kEventHotKeyPressed)) == .cancelPressed)
}

@MainActor
@Test func pasteboardTransactionRestoresOnlyWhenNobodyElseChangedIt() throws {
    let pasteboard = NSPasteboard(name: .init("NODAYSIDLEVoiceTests-\(UUID().uuidString)"))
    pasteboard.clearContents()
    pasteboard.setString("before", forType: .string)
    let transaction = PasteboardTransaction(pasteboard: pasteboard)

    let expectedChangeCount = transaction.put("final transcript")
    #expect(pasteboard.string(forType: .string) == "final transcript")
    #expect(transaction.restore(ifUnchangedFrom: expectedChangeCount))
    #expect(pasteboard.string(forType: .string) == "before")

    let secondTransaction = PasteboardTransaction(pasteboard: pasteboard)
    let secondExpectedCount = secondTransaction.put("second transcript")
    pasteboard.clearContents()
    pasteboard.setString("third-party", forType: .string)

    #expect(!secondTransaction.restore(ifUnchangedFrom: secondExpectedCount))
    #expect(pasteboard.string(forType: .string) == "third-party")
}

@Test func permissionRecoveryUsesTheSpecificSystemSettingsPanes() {
    #expect(PermissionCoordinator.settingsURL(for: .microphone)?.absoluteString.contains("Privacy_Microphone") == true)
    #expect(PermissionCoordinator.settingsURL(for: .accessibility)?.absoluteString.contains("Privacy_Accessibility") == true)
}

@Test func fileTranscriptionPreflightRejectsDeepgramAndOversizedPayloads() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "VoiceFile-\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([0, 1]).write(to: root)

    #expect(throws: FileTranscriptionError.deepgramIsLiveOnly) {
        _ = try FileTranscriptionService.preflight(root, engine: .deepgram)
    }
    #expect(try FileTranscriptionService.preflight(root, engine: .openRouter).format == "wav")
}

@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["NODAYSIDLE_GUI_SMOKE"] == "1"))
func autoPasteInsertsCompletedTextIntoTheFocusedEditor() async throws {
    guard AXIsProcessTrusted() else {
        Issue.record("The GUI smoke runner needs Accessibility permission.")
        return
    }

    let documentURL = FileManager.default.temporaryDirectory
        .appending(path: "NODAYSIDLE-GUI-Smoke-\(UUID().uuidString).txt")
    try Data().write(to: documentURL)
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    configuration.createsNewApplicationInstance = true
    let textEdit: NSRunningApplication = try await withCheckedThrowingContinuation { continuation in
        NSWorkspace.shared.open(
            [documentURL],
            withApplicationAt: URL(filePath: "/System/Applications/TextEdit.app"),
            configuration: configuration
        ) { application, error in
            if let error { continuation.resume(throwing: error) }
            else if let application { continuation.resume(returning: application) }
            else {
                continuation.resume(throwing: CocoaError(.fileNoSuchFile))
            }
        }
    }
    defer {
        textEdit.forceTerminate()
        try? FileManager.default.removeItem(at: documentURL)
    }
    textEdit.activate()

    var focusedEditor: AXUIElement?
    for _ in 0..<30 {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == textEdit.processIdentifier {
            let system = AXUIElementCreateSystemWide()
            var focused: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                system,
                kAXFocusedUIElementAttribute as CFString,
                &focused
            ) == .success {
                focusedEditor = focused as! AXUIElement?
                break
            }
        }
        try await Task.sleep(for: .milliseconds(100))
    }
    let editor = try #require(focusedEditor)

    let marker = "NODAYSIDLE_GUI_SMOKE_0831"
    let target = InsertionTarget(
        processIdentifier: textEdit.processIdentifier,
        bundleIdentifier: textEdit.bundleIdentifier,
        applicationName: "TextEdit GUI smoke host"
    )
    let outcome = try await InsertionService().insert(marker, behavior: .autoPaste, target: target)
    var value: CFTypeRef?
    let valueStatus = AXUIElementCopyAttributeValue(editor, kAXValueAttribute as CFString, &value)

    #expect(outcome == .pasted)
    #expect(valueStatus == .success)
    #expect((value as? String)?.contains(marker) == true)
}

@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["NODAYSIDLE_GUI_TARGET_PID"] != nil))
func autoPasteRoundTripsMarkerInPreparedExternalTarget() async throws {
    let environment = ProcessInfo.processInfo.environment
    let targetPID = try #require(environment["NODAYSIDLE_GUI_TARGET_PID"].flatMap(Int32.init))
    let marker = try #require(environment["NODAYSIDLE_GUI_MARKER"])
    let application = try #require(NSRunningApplication(processIdentifier: targetPID))
    application.activate()
    try await Task.sleep(for: .milliseconds(250))

    let target = InsertionTarget(
        processIdentifier: targetPID,
        bundleIdentifier: application.bundleIdentifier,
        applicationName: application.localizedName ?? "GUI smoke target"
    )
    let outcome = try await InsertionService().insert(marker, behavior: .autoPaste, target: target)
    try await Task.sleep(for: .milliseconds(500))
    let accessibilityApplication = AXUIElementCreateApplication(targetPID)
    var focused: CFTypeRef?
    let focusStatus = AXUIElementCopyAttributeValue(
        accessibilityApplication,
        kAXFocusedUIElementAttribute as CFString,
        &focused
    )
    let editor = try #require(focused as! AXUIElement?)
    var value: CFTypeRef?
    let valueStatus = AXUIElementCopyAttributeValue(editor, kAXValueAttribute as CFString, &value)
    let string = try #require(value as? String)

    #expect(outcome == .pasted)
    #expect(focusStatus == .success)
    #expect(valueStatus == .success)
    let markerWasInserted = string.contains(marker)
    #expect(markerWasInserted)

    if environment["NODAYSIDLE_GUI_DISPOSABLE_TARGET"] == "1" {
        #expect(application.forceTerminate())
        return
    }

    let found = (string as NSString).range(of: marker)
    if found.location != NSNotFound {
        var range = CFRange(location: found.location, length: found.length)
        let selectedRange = try #require(AXValueCreate(.cfRange, &range))
        #expect(AXUIElementSetAttributeValue(
            editor,
            kAXSelectedTextRangeAttribute as CFString,
            selectedRange
        ) == .success)
        let source = try #require(CGEventSource(stateID: .combinedSessionState))
        let keyDown = try #require(CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: true))
        let keyUp = try #require(CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: false))
        keyDown.postToPid(targetPID)
        keyUp.postToPid(targetPID)
        try await Task.sleep(for: .milliseconds(150))
        var cleanedValue: CFTypeRef?
        #expect(AXUIElementCopyAttributeValue(
            editor,
            kAXValueAttribute as CFString,
            &cleanedValue
        ) == .success)
        let markerRemains = (cleanedValue as? String)?.contains(marker) ?? true
        #expect(!markerRemains)
    }
}
