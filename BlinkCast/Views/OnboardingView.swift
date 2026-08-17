import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding")
    private var hasCompletedOnboarding = false

    @State private var page = 0

    private let pageCount = 4

    var body: some View {
        ZStack {
            BlinkBackground()

            VStack(spacing: 28) {
                Spacer()

                Group {
                    switch page {
                    case 0:
                        pageView(
                            icon: "sparkles.rectangle.stack.fill",
                            title: "Welcome to BlinkCast",
                            description:
                                "Fast, private screen sharing designed for Mac, iPhone, and iPad."
                        )

                    case 1:
                        pageView(
                            icon: "bolt.fill",
                            title: "Built for Speed",
                            description:
                                "BlinkCast adapts quality, frame rate, and bitrate to keep your session smooth and responsive."
                        )

                    case 2:
                        pageView(
                            icon: "lock.shield.fill",
                            title: "Private by Design",
                            description:
                                "Your sessions are built around secure connections, host approval, and encrypted communication."
                        )

                    default:
                        pageView(
                            icon: "person.2.wave.2.fill",
                            title: "Ready in Seconds",
                            description:
                                "Choose what to share, create a session, then invite someone with a simple code."
                        )
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    ForEach(
                        0..<pageCount,
                        id: \.self
                    ) { index in
                        Capsule()
                            .fill(
                                index == page
                                ? Color.accentColor
                                : Color.secondary.opacity(0.20)
                            )
                            .frame(
                                width: index == page ? 30 : 8,
                                height: 8
                            )
                    }
                }

                Button {
                    if page < pageCount - 1 {
                        withAnimation(
                            .spring(
                                response: 0.38,
                                dampingFraction: 0.82
                            )
                        ) {
                            page += 1
                        }
                    } else {
                        hasCompletedOnboarding = true
                    }
                } label: {
                    Text(
                        page == pageCount - 1
                        ? "Get Started"
                        : "Continue"
                    )
                }
                .buttonStyle(BlinkPrimaryButtonStyle())
                .frame(maxWidth: 420)
            }
            .padding(34)
        }
    }

    private func pageView(
        icon: String,
        title: String,
        description: String
    ) -> some View {
        BlinkGlassCard {
            VStack(spacing: 26) {
                ZStack {
                    Circle()
                        .fill(
                            Color.accentColor.opacity(0.12)
                        )
                        .frame(
                            width: 128,
                            height: 128
                        )

                    Image(systemName: icon)
                        .font(.system(
                            size: 52,
                            weight: .semibold
                        ))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color.accentColor,
                                    Color.accentColor.opacity(0.55)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(spacing: 12) {
                    Text(title)
                        .font(
                            .system(
                                size: 36,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .multilineTextAlignment(.center)

                    Text(description)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .frame(maxWidth: 520)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: 680)
    }
}

#Preview {
    OnboardingView()
}