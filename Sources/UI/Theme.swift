import SwiftUI

/// AstroLab visual language (v2) — modeled on Arturia's AstroLab stage keyboard:
/// matte snow-white surfaces, light blonde-wood cheeks, blue LED accents, a
/// circular "navigation wheel" color screen, and macro knobs with LED rings.
/// Clean, bright, retro-futuristic. Token names are kept stable across themes.
enum Theme {
    // Cool matte white surfaces
    static let panelLight = Color(red: 0.968, green: 0.972, blue: 0.976)
    static let panelMid   = Color(red: 0.944, green: 0.949, blue: 0.955)
    static let panelDark  = Color(red: 0.900, green: 0.908, blue: 0.918)
    static let card       = Color(red: 0.976, green: 0.980, blue: 0.985)
    static let rail       = Color(red: 0.934, green: 0.940, blue: 0.948)

    // Ink — clean dark slate
    static let etched     = Color(red: 0.150, green: 0.170, blue: 0.205)
    static let etchedSoft = Color(red: 0.470, green: 0.500, blue: 0.545)

    // Accents — one teal/mint family (was blue; it fought the mint + oak)
    static let orange = Color(red: 0.130, green: 0.600, blue: 0.610)   // teal — selection/active
    static let ring   = Color(red: 0.460, green: 0.800, blue: 0.745)   // soft mint — knob LED band
    static let led1   = Color(red: 0.960, green: 0.780, blue: 0.200)   // yellow — "part 1"
    static let led2   = Color(red: 0.240, green: 0.740, blue: 0.440)   // green — "part 2"
    static let record = Color(red: 0.880, green: 0.260, blue: 0.230)   // red dot
    static let gold   = Color(red: 0.860, green: 0.866, blue: 0.872)   // soft cool hairline
    static let amber  = orange

    // Keybed (white keys, cool light bed)
    static let ivory    = Color(red: 0.985, green: 0.988, blue: 0.992)
    static let keybed   = Color(red: 0.850, green: 0.862, blue: 0.878)
    static let blackKey = Color(red: 0.190, green: 0.205, blue: 0.235)

    // Light natural-oak wood cheeks
    static let woodLight = Color(red: 0.860, green: 0.735, blue: 0.540)
    static let woodDark  = Color(red: 0.745, green: 0.610, blue: 0.400)

    static let surface = LinearGradient(
        colors: [Color(red: 0.958, green: 0.962, blue: 0.968), Color(red: 0.928, green: 0.934, blue: 0.942)],
        startPoint: .top, endPoint: .bottom)

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension View {
    /// Clean rounded label.
    func etchedLabel(_ size: CGFloat = 11, soft: Bool = false, weight: Font.Weight = .semibold) -> some View {
        self.font(Theme.mono(size, weight))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(soft ? Theme.etchedSoft : Theme.etched)
    }

    /// Soft molded white card — light top bevel, soft bottom shadow, teal edge when selected.
    func metalCard(corner: CGFloat = 12, selected: Bool = false) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: corner).fill(Theme.card))
            .overlay(  // molded bevel: bright top edge fading to a faint dark bottom
                RoundedRectangle(cornerRadius: corner)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.12), .black.opacity(0.06)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .overlay(RoundedRectangle(cornerRadius: corner)
                .stroke(selected ? Theme.orange : Theme.gold, lineWidth: selected ? 2 : 1))
            .shadow(color: .black.opacity(0.07), radius: 5, x: 0, y: 2)
            .shadow(color: .white.opacity(0.6), radius: 1, x: 0, y: -0.5)   // crisp top edge
            .shadow(color: selected ? Theme.orange.opacity(0.35) : .clear, radius: 7)  // backlit glow
    }
}

/// Matte white panel — soft top light + a faint vignette for a powder-coated
/// metal feel (rather than flat digital white).
struct BrushedAluminum: View {
    var body: some View {
        ZStack(alignment: .top) {
            Theme.surface
            RadialGradient(colors: [.clear, .black.opacity(0.045)],
                           center: .center, startRadius: 220, endRadius: 760)
            LinearGradient(colors: [.white.opacity(0.25), .clear], startPoint: .top, endPoint: .center)
            // bright bevel highlight along the top edge of the casing
            Rectangle().fill(.white.opacity(0.7)).frame(height: 1)
        }
        .ignoresSafeArea()
    }
}

/// Soft hairline divider.
struct GoldHairline: View {
    var body: some View { Rectangle().fill(Theme.gold).frame(height: 1) }
}

/// Small blue status LED.
struct AmberLED: View {
    var on: Bool
    var size: CGFloat = 7
    var body: some View {
        Circle().fill(on ? Theme.orange : Color.black.opacity(0.12))
            .frame(width: size, height: size)
            .overlay(Circle().fill(.white.opacity(on ? 0.45 : 0)).frame(width: size * 0.34, height: size * 0.34)
                .offset(x: -size * 0.12, y: -size * 0.12))
            .shadow(color: on ? Theme.orange.opacity(0.8) : .clear, radius: on ? 4 : 0)
    }
}

/// Faux-wood (bakelite) oak end cheek — grain streaks, a soft sheen, and a
/// beveled highlight/shadow on the edges so it reads as a real rounded cheek.
struct WoodPanel: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.woodLight, Theme.woodDark.opacity(0.95), Theme.woodLight.opacity(0.82)],
                           startPoint: .top, endPoint: .bottom)
            // grain streaks — deterministic, so they don't flicker on redraw
            Canvas { ctx, size in
                var x: CGFloat = 0
                while x < size.width {
                    let h = (Int(x * 7) ^ 0x9E37) & 0xFF
                    let a = 0.05 + Double(h) / 255.0 * 0.11
                    ctx.fill(Path(CGRect(x: x, y: 0, width: 0.8, height: size.height)),
                             with: .color(.black.opacity(a)))
                    x += CGFloat(1.4 + Double(h % 3))
                }
            }
            .blendMode(.multiply)
            // soft lengthwise sheen
            LinearGradient(colors: [.white.opacity(0.20), .clear, .clear, .white.opacity(0.06)],
                           startPoint: .leading, endPoint: .trailing)
                .blendMode(.softLight)
            // beveled edges
            HStack(spacing: 0) {
                Rectangle().fill(.white.opacity(0.30)).frame(width: 1)
                Spacer()
                Rectangle().fill(.black.opacity(0.18)).frame(width: 1)
            }
        }
    }
}

/// Dotted grille texture for empty states (light dots on white).
struct PerforatedGrille: View {
    var dotColor: Color = .black.opacity(0.10)
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

// MARK: - AstroLab signature pieces

/// Macro knob with an LED position ring (blue by default). Vertical drag to turn.
struct LEDRingKnob: View {
    var value: Double
    var range: ClosedRange<Double> = 0...1
    var size: CGFloat = 42
    var ring: Color = Theme.ring       // soft mint LED band, like the AstroLab
    var bipolar: Bool = false          // centered params light from 12 o'clock outward
    var onChange: (Double) -> Void

    @State private var dragStart: Double?
    @State private var live: Double?
    private var shown: Double {
        let v = live ?? value
        let span = range.upperBound - range.lowerBound
        return span > 0 ? min(1, max(0, (v - range.lowerBound) / span)) : 0
    }

    /// Lit arc as trim fractions of the full circle (the 270° arc occupies 0…0.75).
    private var litArc: (CGFloat, CGFloat) {
        if bipolar {
            let half = shown - 0.5                  // -0.5…+0.5, 0 = center (top)
            let center: CGFloat = 0.375             // midpoint of the 0.75 arc = 12 o'clock
            return half >= 0 ? (center, center + CGFloat(half) * 0.75)
                             : (center + CGFloat(half) * 0.75, center)
        }
        return (0, 0.75 * CGFloat(shown))
    }

    var body: some View {
        ZStack {
            // Recessed channel — inner shadow up top, light at the bottom (inset look).
            Circle().stroke(LinearGradient(colors: [.black.opacity(0.13), .white.opacity(0.55)],
                                           startPoint: .top, endPoint: .bottom), lineWidth: 3.5)
                .frame(width: size, height: size)
            if bipolar {
                Capsule().fill(Color.black.opacity(0.18)).frame(width: 1.5, height: 5)
                    .offset(y: -size / 2)
            }
            // Lit mint LED band — soft glow on the white
            Circle().trim(from: litArc.0, to: litArc.1)
                .stroke(ring, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(135))
                .frame(width: size, height: size)
                .shadow(color: ring.opacity(0.75), radius: 3)
            // Brushed/spun aluminium cap (domed)
            Circle()
                .fill(AngularGradient(
                    colors: [Color(white: 0.96), Color(white: 0.74), Color(white: 0.92),
                             Color(white: 0.70), Color(white: 0.94), Color(white: 0.74), Color(white: 0.96)],
                    center: .center))
                .overlay(Circle().fill(RadialGradient(colors: [.white.opacity(0.55), .clear],
                                                      center: .center, startRadius: 1, endRadius: size * 0.42)))
                .overlay(Circle().stroke(.black.opacity(0.16), lineWidth: 0.6))
                .frame(width: size - 13, height: size - 13)
                .shadow(color: .black.opacity(0.20), radius: 2, y: 1)
            Capsule().fill(Theme.etched.opacity(0.65))
                .frame(width: 2, height: size * 0.17)
                .offset(y: -size * 0.16)
                .rotationEffect(.degrees(-135 + 270 * shown))
        }
        .frame(width: size + 12, height: size + 12)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if dragStart == nil { dragStart = value }
                    let span = range.upperBound - range.lowerBound
                    let nv = min(range.upperBound, max(range.lowerBound,
                        (dragStart ?? value) + Double(-v.translation.height) / 120.0 * span))
                    live = nv; onChange(nv)
                }
                .onEnded { _ in dragStart = nil; live = nil }
        )
    }
}

/// The AstroLab signature: a circular navigation-wheel color screen showing the
/// current sound, ringed by a blue LED bezel.
struct NavWheel: View {
    var title: String
    var subtitle: String
    var glyph: String = "waveform"
    var lit: Bool = true
    var size: CGFloat = 92

    var body: some View {
        ZStack {
            Circle().fill(Theme.card)
                .overlay(Circle().stroke(Theme.gold, lineWidth: 1))
                .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
            Circle().trim(from: 0, to: 0.82)
                .stroke(lit ? Theme.orange : Theme.etchedSoft.opacity(0.4),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(126))
                .frame(width: size - 8, height: size - 8)
                .shadow(color: lit ? Theme.orange.opacity(0.6) : .clear, radius: 3)
            Circle().fill(Color(red: 0.07, green: 0.085, blue: 0.11))
                .frame(width: size - 22, height: size - 22)
                .overlay(Circle().stroke(.white.opacity(0.06), lineWidth: 1))
            VStack(spacing: 2) {
                Image(systemName: glyph).font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.orange)
                Text(title).font(Theme.mono(11, .bold)).foregroundStyle(.white).lineLimit(1)
                Text(subtitle).font(Theme.mono(7, .medium)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
            .frame(width: size - 30)
        }
        .frame(width: size, height: size)
    }
}
