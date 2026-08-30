import SwiftUI

enum VoiceStyle {
    static let coral = Color(red: 0.96, green: 0.31, blue: 0.30)
    static let card = Color.primary.opacity(0.06)
    static let border = Color.primary.opacity(0.11)
    static let success = Color(red: 0.23, green: 0.72, blue: 0.49)
    static let warning = Color(red: 0.96, green: 0.62, blue: 0.20)
}

extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}

struct SectionCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(VoiceStyle.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(VoiceStyle.border)
            }
    }
}

struct PermissionBadge: View {
    let title: String
    let state: PermissionState

    var body: some View {
        Label(title, systemImage: state == .granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(state == .granted ? VoiceStyle.success : VoiceStyle.warning)
    }
}
