//
//  DesignSystem.swift
//  ETF Calculator
//

import SwiftUI

/// A color world for hero cards and the tinted background glow.
enum Palette: String, CaseIterable, Identifiable {
    case emerald, ocean, indigo, violet, rose, sunset, graphite

    var id: Self { self }

    var name: LocalizedStringResource {
        switch self {
        case .emerald: "Emerald"
        case .ocean: "Ocean"
        case .indigo: "Indigo"
        case .violet: "Violet"
        case .rose: "Rosé"
        case .sunset: "Sunset"
        case .graphite: "Graphite"
        }
    }

    /// Tint for the background glow.
    var tint: Color {
        switch self {
        case .emerald: .green
        case .ocean: .blue
        case .indigo: .indigo
        case .violet: .purple
        case .rose: .pink
        case .sunset: .orange
        case .graphite: .gray
        }
    }

    /// 3×3 mesh colors. All have at least 5:1 contrast to white text.
    var meshColors: [Color] {
        switch self {
        case .emerald:
            [
                Color(red: 0.02, green: 0.42, blue: 0.33), Color(red: 0.04, green: 0.49, blue: 0.35), Color(red: 0.05, green: 0.40, blue: 0.45),
                Color(red: 0.03, green: 0.36, blue: 0.30), Color(red: 0.09, green: 0.49, blue: 0.34), Color(red: 0.04, green: 0.34, blue: 0.48),
                Color(red: 0.02, green: 0.28, blue: 0.27), Color(red: 0.03, green: 0.36, blue: 0.36), Color(red: 0.05, green: 0.26, blue: 0.44)
            ]
        case .ocean:
            [
                Color(red: 0.02, green: 0.30, blue: 0.62), Color(red: 0.04, green: 0.36, blue: 0.70), Color(red: 0.02, green: 0.40, blue: 0.58),
                Color(red: 0.03, green: 0.24, blue: 0.54), Color(red: 0.06, green: 0.38, blue: 0.72), Color(red: 0.02, green: 0.36, blue: 0.50),
                Color(red: 0.02, green: 0.18, blue: 0.42), Color(red: 0.03, green: 0.24, blue: 0.50), Color(red: 0.02, green: 0.28, blue: 0.42)
            ]
        case .indigo:
            [
                Color(red: 0.20, green: 0.18, blue: 0.62), Color(red: 0.28, green: 0.22, blue: 0.70), Color(red: 0.40, green: 0.20, blue: 0.62),
                Color(red: 0.14, green: 0.20, blue: 0.56), Color(red: 0.26, green: 0.30, blue: 0.74), Color(red: 0.36, green: 0.18, blue: 0.56),
                Color(red: 0.10, green: 0.16, blue: 0.44), Color(red: 0.16, green: 0.20, blue: 0.52), Color(red: 0.26, green: 0.14, blue: 0.46)
            ]
        case .violet:
            [
                Color(red: 0.40, green: 0.16, blue: 0.62), Color(red: 0.50, green: 0.20, blue: 0.66), Color(red: 0.62, green: 0.18, blue: 0.52),
                Color(red: 0.34, green: 0.14, blue: 0.56), Color(red: 0.52, green: 0.26, blue: 0.72), Color(red: 0.58, green: 0.16, blue: 0.46),
                Color(red: 0.26, green: 0.10, blue: 0.44), Color(red: 0.36, green: 0.14, blue: 0.52), Color(red: 0.46, green: 0.12, blue: 0.40)
            ]
        case .rose:
            [
                Color(red: 0.66, green: 0.14, blue: 0.36), Color(red: 0.70, green: 0.18, blue: 0.42), Color(red: 0.62, green: 0.12, blue: 0.50),
                Color(red: 0.58, green: 0.12, blue: 0.32), Color(red: 0.72, green: 0.20, blue: 0.40), Color(red: 0.54, green: 0.12, blue: 0.48),
                Color(red: 0.46, green: 0.08, blue: 0.26), Color(red: 0.54, green: 0.10, blue: 0.32), Color(red: 0.44, green: 0.08, blue: 0.40)
            ]
        case .sunset:
            [
                Color(red: 0.70, green: 0.30, blue: 0.06), Color(red: 0.69, green: 0.33, blue: 0.07), Color(red: 0.72, green: 0.22, blue: 0.16),
                Color(red: 0.62, green: 0.26, blue: 0.06), Color(red: 0.66, green: 0.34, blue: 0.08), Color(red: 0.64, green: 0.18, blue: 0.18),
                Color(red: 0.50, green: 0.20, blue: 0.06), Color(red: 0.58, green: 0.24, blue: 0.08), Color(red: 0.50, green: 0.14, blue: 0.16)
            ]
        case .graphite:
            [
                Color(red: 0.26, green: 0.28, blue: 0.32), Color(red: 0.32, green: 0.34, blue: 0.38), Color(red: 0.22, green: 0.24, blue: 0.30),
                Color(red: 0.20, green: 0.22, blue: 0.26), Color(red: 0.34, green: 0.36, blue: 0.40), Color(red: 0.18, green: 0.20, blue: 0.24),
                Color(red: 0.12, green: 0.13, blue: 0.16), Color(red: 0.16, green: 0.17, blue: 0.20), Color(red: 0.10, green: 0.11, blue: 0.14)
            ]
        }
    }

    static let storageKey = "appearance.palette"
}

/// Semantic card roles. Each tab has its own default palette unless
/// a Premium user picked one palette for the whole app.
enum CardTheme {
    case growth, goal, payout, scenarios

    var defaultPalette: Palette {
        switch self {
        case .growth: .emerald
        case .goal: .indigo
        case .payout: .sunset
        case .scenarios: .violet
        }
    }
}

extension EnvironmentValues {
    /// App-wide palette chosen in Settings (Premium); `nil` uses per-tab colors.
    @Entry var paletteOverride: Palette?
}

/// Mesh gradient background shared by hero cards and palette swatches.
struct PaletteMesh: View {
    let palette: Palette

    var body: some View {
        ZStack {
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.55, 0], [1, 0],
                    [0, 0.45], [0.6, 0.4], [1, 0.55],
                    [0, 1], [0.45, 1], [1, 1]
                ],
                colors: palette.meshColors
            )
            // Soft highlight in the top-left corner for depth.
            RadialGradient(colors: [.white.opacity(0.10), .clear], center: .topLeading, startRadius: 0, endRadius: 320)
        }
    }
}

/// Wallet-style card with a mesh gradient, used for the headline result of each tab.
struct HeroCard<Content: View>: View {
    let theme: CardTheme
    @ViewBuilder let content: Content

    @Environment(\.paletteOverride) private var paletteOverride

    var body: some View {
        content
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                PaletteMesh(palette: paletteOverride ?? theme.defaultPalette)
                    .animation(.smooth, value: paletteOverride)
            }
            .clipShape(.rect(cornerRadius: 26, style: .continuous))
            .environment(\.colorScheme, .dark)
    }
}

/// Grouped background with a subtle tint glow behind the large title.
private struct ThemedBackground: ViewModifier {
    let theme: CardTheme

    @Environment(\.paletteOverride) private var paletteOverride

    func body(content: Content) -> some View {
        let tint = (paletteOverride ?? theme.defaultPalette).tint
        content
            .scrollContentBackground(.hidden)
            .background {
                ZStack(alignment: .top) {
                    Color(.systemGroupedBackground)
                    LinearGradient(
                        colors: [tint.opacity(0.22), tint.opacity(0.06), .clear],
                        startPoint: .top,
                        endPoint: .init(x: 0.5, y: 0.45)
                    )
                }
                .ignoresSafeArea()
                .animation(.smooth, value: paletteOverride)
            }
    }
}

extension View {
    /// Places a hero card edge-to-edge inside a list section.
    func heroRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
    }

    func themedBackground(_ theme: CardTheme) -> some View {
        modifier(ThemedBackground(theme: theme))
    }
}

/// White symbol on a colored rounded square, as used in the Settings app.
struct IconTile: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 29

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: .rect(cornerRadius: size * 0.24))
            .accessibilityHidden(true)
    }
}

/// Capsule on hero cards, e.g. "↗ +6,186 € (48 %)".
struct CardBadge<Label: View>: View {
    @ViewBuilder let label: Label

    var body: some View {
        label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.18), in: .capsule)
    }
}
