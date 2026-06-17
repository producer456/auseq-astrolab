import SwiftUI

/// AUSeq visual language — "brushed aluminum hi-fi" modeled on a silver cassette
/// deck (mood, not metaphor): anodized silver panels, dark etched mono labels,
/// safety-orange action accents, brass hairlines, amber LED indicators.
/// Finish is hybrid: clean modern layout with a few tactile signature pieces
/// (perforated grille, amber LEDs, brushed metal).
enum Theme {
    // Aluminum surfaces (light)
    static let panelLight = Color(red: 0.88, green: 0.89, blue: 0.90)
    static let panelMid   = Color(red: 0.80, green: 0.81, blue: 0.82)
    static let panelDark  = Color(red: 0.69, green: 0.70, blue: 0.72)
    static let card       = Color(red: 0.91, green: 0.92, blue: 0.93)
    static let rail       = Color(red: 0.84, green: 0.85, blue: 0.86)

    // Ink — low-contrast "etched into metal"
    static let etched     = Color(red: 0.20, green: 0.21, blue: 0.23)
    static let etchedSoft = Color(red: 0.44, green: 0.45, blue: 0.47)

    // Accents
    static let orange = Color(red: 0.96, green: 0.49, blue: 0.12)   // safety orange
    static let gold   = Color(red: 0.80, green: 0.64, blue: 0.32)   // brass hairline
    static let amber  = Color(red: 1.00, green: 0.72, blue: 0.22)   // LED

    // Keybed
    static let ivory    = Color(red: 0.96, green: 0.95, blue: 0.91)
    static let keybed   = Color(red: 0.15, green: 0.15, blue: 0.17)
    static let blackKey = Color(red: 0.11, green: 0.11, blue: 0.12)

    // Walnut wood case (side panels)
    static let woodLight = Color(red: 0.430, green: 0.290, blue: 0.175)
    static let woodDark  = Color(red: 0.250, green: 0.165, blue: 0.095)

    static let surface = LinearGradient(
        colors: [panelLight, panelMid, panelDark],
        startPoint: .top, endPoint: .bottom)

    /// Technical mono caps — used for all hardware-style labels.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension View {
    /// Etched mono-caps label styling for hardware labels.
    func etchedLabel(_ size: CGFloat = 11, soft: Bool = false, weight: Font.Weight = .semibold) -> some View {
        self.font(Theme.mono(size, weight))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(soft ? Theme.etchedSoft : Theme.etched)
    }

    /// Raised brushed-metal card, optionally selected (orange edge) vs idle (brass edge).
    func metalCard(corner: CGFloat = 10, selected: Bool = false) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: corner)
                    .fill(Theme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: corner)
                            .fill(LinearGradient(colors: [.white.opacity(0.55), .clear],
                                                 startPoint: .top, endPoint: .bottom))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner)
                    .stroke(selected ? Theme.orange : Theme.gold.opacity(0.45),
                            lineWidth: selected ? 2 : 1)
            )
    }
}

/// Full-bleed brushed aluminum background (gradient + faint vertical brush grain).
struct BrushedAluminum: View {
    var body: some View {
        ZStack {
            Theme.surface
            Canvas { ctx, size in
                var x: CGFloat = 0
                while x < size.width {
                    ctx.fill(Path(CGRect(x: x, y: 0, width: 0.5, height: size.height)),
                             with: .color(.white.opacity(0.05)))
                    x += 3
                }
            }
            .blendMode(.overlay)
        }
        .ignoresSafeArea()
    }
}

/// Thin brass hairline with a subtle highlight — the deck's gold pinstripe.
struct GoldHairline: View {
    var body: some View {
        Rectangle().fill(Theme.gold.opacity(0.7)).frame(height: 1)
            .overlay(Rectangle().fill(.white.opacity(0.35)).frame(height: 0.5).offset(y: -0.5))
    }
}

/// Small amber status LED with a soft glow when lit.
struct AmberLED: View {
    var on: Bool
    var size: CGFloat = 7
    var body: some View {
        Circle()
            .fill(on ? Theme.amber : Color.black.opacity(0.22))
            .frame(width: size, height: size)
            .overlay(Circle().stroke(.black.opacity(0.25), lineWidth: 0.5))
            .shadow(color: on ? Theme.amber.opacity(0.9) : .clear, radius: on ? 4 : 0)
    }
}

/// Walnut wood case panel (vertical grain) — the synth's end cheeks.
struct WoodPanel: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.woodLight, Theme.woodDark, Theme.woodLight.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                var x: CGFloat = 0
                while x < size.width {
                    ctx.fill(Path(CGRect(x: x, y: 0, width: 0.7, height: size.height)),
                             with: .color(.black.opacity(0.07)))
                    x += 2.5
                }
            }
            .blendMode(.multiply)
        }
    }
}

/// Perforated speaker-grille texture — signature tactile piece for empty states.
struct PerforatedGrille: View {
    var dotColor: Color = .black.opacity(0.16)
    var body: some View {
        Canvas { ctx, size in
            let r: CGFloat = 1.8, gap: CGFloat = 7
            var y = gap
            while y < size.height {
                var x = gap
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)),
                             with: .color(dotColor))
                    x += gap
                }
                y += gap
            }
        }
    }
}
