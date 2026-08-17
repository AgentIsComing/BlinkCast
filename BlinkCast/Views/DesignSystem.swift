import SwiftUI

struct BlinkBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.12),
                    .clear
                ],
                center: .topLeading,
                startRadius: 20,
                endRadius: 560
            )

            RadialGradient(
                colors: [
                    Color.purple.opacity(colorScheme == .dark ? 0.13 : 0.07),
                    .clear
                ],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 640
            )
        }
        .ignoresSafeArea()
    }

    private var backgroundColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.035, green: 0.045, blue: 0.085),
                Color(red: 0.022, green: 0.028, blue: 0.055),
                Color(red: 0.014, green: 0.018, blue: 0.037)
            ]
        }

        return [
            Color(red: 0.965, green: 0.975, blue: 1.0),
            Color(red: 0.945, green: 0.96, blue: 0.995),
            Color(red: 0.985, green: 0.985, blue: 1.0)
        ]
    }
}

struct BlinkGlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(22)
            .background {
                RoundedRectangle(
                    cornerRadius: 26,
                    style: .continuous
                )
                .fill(cardFill)
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: 26,
                    style: .continuous
                )
                .stroke(
                    borderColor,
                    lineWidth: 1
                )
            }
            .shadow(
                color: Color.black.opacity(
                    colorScheme == .dark ? 0.26 : 0.08
                ),
                radius: 24,
                x: 0,
                y: 12
            )
    }

    private var cardFill: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.085),
                    Color.white.opacity(0.045)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                Color.white.opacity(0.92),
                Color.white.opacity(0.72)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.11)
            : Color.black.opacity(0.06)
    }
}

struct BlinkPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor,
                            Color.accentColor.opacity(0.72)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(
                    color: Color.accentColor.opacity(
                        configuration.isPressed ? 0.18 : 0.34
                    ),
                    radius: configuration.isPressed ? 7 : 16,
                    y: configuration.isPressed ? 2 : 7
                )
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(
                .spring(response: 0.22, dampingFraction: 0.82),
                value: configuration.isPressed
            )
    }
}

struct BlinkSecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
                .fill(
                    colorScheme == .dark
                        ? Color.white.opacity(0.07)
                        : Color.white.opacity(0.84)
                )
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
                .stroke(
                    colorScheme == .dark
                        ? Color.white.opacity(0.10)
                        : Color.black.opacity(0.06),
                    lineWidth: 1
                )
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct BlinkSectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.title2.bold())

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct BlinkStatusPill: View {
    let text: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                tint.opacity(0.13),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(
                        tint.opacity(0.22),
                        lineWidth: 1
                    )
            }
    }
}

struct BlinkIconBadge: View {
    let systemImage: String
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: size * 0.28,
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.25),
                        Color.accentColor.opacity(0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            Image(systemName: systemImage)
                .font(
                    .system(
                        size: size * 0.44,
                        weight: .semibold
                    )
                )
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: size, height: size)
    }
}

struct BlinkSidebarBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: sidebarColors,
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var sidebarColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.055, green: 0.065, blue: 0.11),
                Color(red: 0.035, green: 0.042, blue: 0.075)
            ]
        }

        return [
            Color(red: 0.93, green: 0.95, blue: 0.99),
            Color(red: 0.90, green: 0.93, blue: 0.98)
        ]
    }
}

struct BlinkHeroPanel: View {
    let title: String
    let subtitle: String

    var body: some View {
        BlinkGlassCard {
            HStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(
                        cornerRadius: 22,
                        style: .continuous
                    )
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.28),
                                Color.purple.opacity(0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 78, height: 78)

                    Image(systemName: "bolt.horizontal.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(
                            .system(
                                size: 34,
                                weight: .bold,
                                design: .rounded
                            )
                        )

                    Text(subtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                BlinkStatusPill(
                    text: "Ready",
                    systemImage: "checkmark.circle.fill",
                    tint: .green
                )
            }
        }
    }
}