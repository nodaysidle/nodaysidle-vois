import AppKit
import ApplicationServices
import Foundation

@MainActor
final class PasteboardTransaction {
    private let pasteboard: NSPasteboard
    private let snapshot: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        snapshot = pasteboard.pasteboardItems?.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        } ?? []
    }

    @discardableResult
    func put(_ text: String) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return pasteboard.changeCount
    }

    @discardableResult
    func restore(ifUnchangedFrom expectedChangeCount: Int) -> Bool {
        guard pasteboard.changeCount == expectedChangeCount else { return false }
        pasteboard.clearContents()
        let items = snapshot.map { representations in
            let item = NSPasteboardItem()
            representations.forEach { item.setData($0.value, forType: $0.key) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
        return true
    }
}

struct InsertionTarget: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let applicationName: String
}

enum InsertionOutcome: Equatable, Sendable {
    case pasted
    case copied
    case previewRequired(String)
}

enum InsertionError: Error, Equatable {
    case emptyText
    case accessibilityDenied
    case targetUnavailable
    case eventCreationFailed
}

extension InsertionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .emptyText: "There is no completed text to insert."
        case .accessibilityDenied: "Allow Accessibility access to auto-paste."
        case .targetUnavailable: "The previous application is no longer available."
        case .eventCreationFailed: "macOS could not create the paste event."
        }
    }
}

@MainActor
final class InsertionService {
    func captureTarget() -> InsertionTarget? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        return InsertionTarget(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            applicationName: application.localizedName ?? "Unknown application"
        )
    }

    func insert(
        _ text: String,
        behavior: InsertionBehavior,
        target: InsertionTarget?
    ) async throws -> InsertionOutcome {
        guard !text.isEmpty else { throw InsertionError.emptyText }
        switch behavior {
        case .clipboard:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return .copied
        case .preview:
            return .previewRequired(text)
        case .autoPaste:
            guard AXIsProcessTrusted() else { throw InsertionError.accessibilityDenied }
            guard let target,
                  let application = NSRunningApplication(processIdentifier: target.processIdentifier) else {
                throw InsertionError.targetUnavailable
            }
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processIdentifier {
                application.activate()
                try await Task.sleep(for: .milliseconds(100))
            }
            if insertDirectly(text, into: target) { return .pasted }

            let transaction = PasteboardTransaction()
            let expectedChangeCount = transaction.put(text)
            if pressPasteMenuItem(in: target.processIdentifier) {
                try await Task.sleep(for: .milliseconds(150))
                _ = transaction.restore(ifUnchangedFrom: expectedChangeCount)
                return .pasted
            }
            guard let source = CGEventSource(stateID: .combinedSessionState),
                  let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
                _ = transaction.restore(ifUnchangedFrom: expectedChangeCount)
                throw InsertionError.eventCreationFailed
            }
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            try await Task.sleep(for: .milliseconds(150))
            _ = transaction.restore(ifUnchangedFrom: expectedChangeCount)
            return .pasted
        }
    }

    private func insertDirectly(_ text: String, into target: InsertionTarget) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
            return false
        }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        ) == .success, let focused else { return false }
        let element = focused as! AXUIElement
        var valueBefore: CFTypeRef?
        var selectedTextBefore: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &valueBefore
        ) == .success, let stringBefore = valueBefore as? String else { return false }
        _ = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedTextBefore
        )
        guard AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        ) == .success else { return false }
        var valueAfter: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &valueAfter
        ) == .success, let stringAfter = valueAfter as? String else { return false }
        return stringAfter.contains(text)
            && (stringAfter != stringBefore || selectedTextBefore as? String == text)
    }

    private func pressPasteMenuItem(in processIdentifier: pid_t) -> Bool {
        let application = AXUIElementCreateApplication(processIdentifier)
        var menuBar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXMenuBarAttribute as CFString,
            &menuBar
        ) == .success, let menuBar else { return false }
        return pressPasteMenuItem(in: menuBar as! AXUIElement, depth: 0)
    }

    private func pressPasteMenuItem(in element: AXUIElement, depth: Int) -> Bool {
        guard depth < 4 else { return false }
        var identifier: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            kAXIdentifierAttribute as CFString,
            &identifier
        ) == .success, identifier as? String == "paste:" {
            return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
        }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &children
        ) == .success, let children = children as? [AXUIElement] else { return false }
        return children.contains { pressPasteMenuItem(in: $0, depth: depth + 1) }
    }
}
