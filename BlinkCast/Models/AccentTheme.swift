import SwiftUI

enum AccentTheme: String, CaseIterable, Identifiable {
    case blue
    case red
    case orange
    case yellow
    case green
    case purple
    case pink

    var id: String {
        rawValue
    }

    var title: String {
        rawValue.capitalized
    }

    var color: Color {
        switch self {
        case .blue:
            return .blue

        case .red:
            return .red

        case .orange:
            return .orange

        case .yellow:
            return .yellow

        case .green:
            return .green

        case .purple:
            return .purple

        case .pink:
            return .pink
        }
    }

    static func color(for rawValue: String) -> Color {
        AccentTheme(rawValue: rawValue)?.color ?? .blue
    }
}