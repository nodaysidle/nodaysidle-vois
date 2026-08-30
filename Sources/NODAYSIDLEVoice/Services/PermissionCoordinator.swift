import AppKit
import AVFoundation
import ApplicationServices
import Foundation

enum SystemPermission: Sendable {
    case microphone
    case accessibility
}

enum PermissionState: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
    case restricted
}

@MainActor
final class PermissionCoordinator {
    func state(for permission: SystemPermission) -> PermissionState {
        switch permission {
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .notDetermined: .notDetermined
            case .authorized: .granted
            case .denied: .denied
            case .restricted: .restricted
            @unknown default: .denied
            }
        case .accessibility:
            AXIsProcessTrusted() ? .granted : .denied
        }
    }

    func requestMicrophone() async -> Bool {
        switch state(for: .microphone) {
        case .granted: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted: false
        }
    }

    func requestAccessibilityPrompt() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openSettings(for permission: SystemPermission) {
        if let url = Self.settingsURL(for: permission) { NSWorkspace.shared.open(url) }
    }

    nonisolated static func settingsURL(for permission: SystemPermission) -> URL? {
        let anchor = switch permission {
        case .microphone: "Privacy_Microphone"
        case .accessibility: "Privacy_Accessibility"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }
}
