import AppKit
import Carbon
import Foundation

struct HotkeyDescriptor: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let pushToTalk = Self(keyCode: 49, modifiers: UInt32(controlKey))
    static let toggle = Self(keyCode: 49, modifiers: UInt32(optionKey | shiftKey))

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        return value
    }

    var displayName: String {
        let modifierNames: [(UInt32, String)] = [
            (UInt32(shiftKey), "⇧"),
            (UInt32(controlKey), "⌃"),
            (UInt32(optionKey), "⌥"),
            (UInt32(cmdKey), "⌘"),
        ]
        let prefix = modifierNames.compactMap { modifiers & $0.0 == 0 ? nil : $0.1 }
        let key = switch keyCode {
        case 49: "Space"
        case 36: "Return"
        case 48: "Tab"
        case 53: "Escape"
        default: "Key \(keyCode)"
        }
        return (prefix + [key]).joined(separator: " ")
    }
}

enum HotkeyAction: Equatable, Sendable {
    case pushToTalkPressed
    case pushToTalkReleased
    case togglePressed
    case cancelPressed
}

enum HotkeyRegistrationError: Error, Equatable {
    case conflict(String)
}

extension HotkeyRegistrationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .conflict(let name): "The \(name) shortcut is already in use."
        }
    }
}

@MainActor
final class HotkeyController {
    private static let signature: OSType = 0x4E445356 // NDSV
    private var eventHandler: EventHandlerRef?
    private var registrations: [EventHotKeyRef] = []
    private var cancelRegistration: EventHotKeyRef?
    private let onAction: (HotkeyAction) -> Void

    init(onAction: @escaping (HotkeyAction) -> Void) {
        self.onAction = onAction
    }

    func register(
        pushToTalk: HotkeyDescriptor = .pushToTalk,
        toggle: HotkeyDescriptor = .toggle
    ) throws {
        unregister()
        if eventHandler == nil {
            var specs = [
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
            ]
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                hotkeyEventHandler,
                specs.count,
                &specs,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandler
            )
            guard status == noErr else { throw HotkeyRegistrationError.conflict("event handler") }
        }

        do {
            try register(pushToTalk, id: 1, name: "Push to talk")
            try register(toggle, id: 2, name: "Start / stop")
        } catch {
            unregister()
            throw error
        }
    }

    func unregister() {
        registrations.forEach { UnregisterEventHotKey($0) }
        registrations.removeAll(keepingCapacity: true)
        unregisterCancel()
    }

    func registerCancel() throws {
        guard cancelRegistration == nil else { return }
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            53,
            0,
            EventHotKeyID(signature: Self.signature, id: 3),
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else { throw HotkeyRegistrationError.conflict("Escape") }
        cancelRegistration = reference
    }

    func unregisterCancel() {
        if let cancelRegistration { UnregisterEventHotKey(cancelRegistration) }
        cancelRegistration = nil
    }

    nonisolated static func action(id: UInt32, eventKind: UInt32) -> HotkeyAction? {
        switch (id, eventKind) {
        case (1, UInt32(kEventHotKeyPressed)): .pushToTalkPressed
        case (1, UInt32(kEventHotKeyReleased)): .pushToTalkReleased
        case (2, UInt32(kEventHotKeyPressed)): .togglePressed
        case (3, UInt32(kEventHotKeyPressed)): .cancelPressed
        default: nil
        }
    }

    fileprivate func receive(id: UInt32, eventKind: UInt32) {
        if let action = Self.action(id: id, eventKind: eventKind) { onAction(action) }
    }

    private func register(_ descriptor: HotkeyDescriptor, id: UInt32, name: String) throws {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            descriptor.keyCode,
            descriptor.modifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else { throw HotkeyRegistrationError.conflict(name) }
        registrations.append(reference)
    }
}

private let hotkeyEventHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotkeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotkeyID
    )
    guard status == noErr else { return status }
    let controller = Unmanaged<HotkeyController>.fromOpaque(userData).takeUnretainedValue()
    let kind = GetEventKind(event)
    Task { @MainActor in controller.receive(id: hotkeyID.id, eventKind: kind) }
    return noErr
}
