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

    /// Near-black casing that runs to the screen edges so the app blends into the
    /// iPad's physical bezel — the faceplate sits recessed inside it.
    static let bezel = Color(red: 0.045, green: 0.050, blue: 0.060)

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

/// Selectable wood finish for the deck/inlays.
enum WoodTone: String, CaseIterable, Identifiable {
    case oak, walnut
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var next: WoodTone { self == .oak ? .walnut : .oak }

    var light: Color {
        switch self {
        case .oak:    return Color(red: 0.860, green: 0.735, blue: 0.540)
        case .walnut: return Color(red: 0.470, green: 0.335, blue: 0.235)
        }
    }
    var dark: Color {
        switch self {
        case .oak:    return Color(red: 0.745, green: 0.610, blue: 0.400)
        case .walnut: return Color(red: 0.300, green: 0.205, blue: 0.140)
        }
    }
    /// Engraving/ink color that reads on this wood.
    var ink: Color {
        switch self {
        case .oak:    return Theme.etched
        case .walnut: return Color(red: 0.93, green: 0.88, blue: 0.80)
        }
    }
}

/// Horizontal-grain wood "deck" — the wood rolled in as an internal surface (the
/// instrument's top panel behind the screen/branding), not an edge cheek. Grain
/// runs along the band; top/bottom bevels read as a raised panel.
struct WoodDeck: View {
    var tone: WoodTone = .oak
    var body: some View {
        ZStack {
            LinearGradient(colors: [tone.light.opacity(0.96), tone.dark.opacity(0.94), tone.light.opacity(0.82)],
                           startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                var y: CGFloat = 0
                while y < size.height {
                    let h = (Int(y * 7) ^ 0x9E37) & 0xFF
                    let a = 0.04 + Double(h) / 255.0 * 0.09
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.8)),
                             with: .color(.black.opacity(a)))
                    y += CGFloat(1.6 + Double(h % 3))
                }
            }
            .blendMode(.multiply)
            LinearGradient(colors: [.white.opacity(0.16), .clear, .white.opacity(0.05)],
                           startPoint: .top, endPoint: .bottom)
                .blendMode(.softLight)
            VStack(spacing: 0) {
                Rectangle().fill(.white.opacity(0.22)).frame(height: 1)
                Spacer()
                Rectangle().fill(.black.opacity(0.24)).frame(height: 1)
            }
        }
    }
}

/// Recessed circular well that makes a control look milled/inlaid into the wood
/// deck — dark carved interior, inner shadow up top, a raised wood lip below.
struct WoodInlayCircle: ViewModifier {
    var size: CGFloat = 40
    var tone: WoodTone = .oak
    func body(content: Content) -> some View {
        content
            .frame(width: size, height: size)
            .background(
                Circle().fill(
                    RadialGradient(colors: [tone.dark.opacity(0.98), tone.dark.opacity(0.70)],
                                   center: .center, startRadius: 1, endRadius: size * 0.62)   // concave recess
                        .shadow(.inner(color: .black.opacity(0.62), radius: 3, y: 1.5))
                        .shadow(.inner(color: .white.opacity(0.10), radius: 1, y: -1))
                )
            )
            .overlay(Circle().stroke(.black.opacity(0.38), lineWidth: 0.75))                  // carved rim
            .overlay(Circle().strokeBorder(.white.opacity(0.10), lineWidth: 0.5))             // faint top sheen
            .overlay(                                                                         // raised wood lip below
                Circle().stroke(.white.opacity(0.24), lineWidth: 1)
                    .mask(LinearGradient(colors: [.clear, .black], startPoint: .center, endPoint: .bottom))
                    .offset(y: 0.7)
            )
    }
}

/// Recessed rounded-rect well — for text/grouped controls inlaid into the wood
/// (tempo, quantize, bar count).
struct WoodInlayPill: ViewModifier {
    var tone: WoodTone = .oak
    var hPad: CGFloat = 10
    var vPad: CGFloat = 6
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, hPad).padding(.vertical, vPad)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(
                    tone.dark.opacity(0.92)
                        .shadow(.inner(color: .black.opacity(0.60), radius: 2.5, y: 1.5))
                        .shadow(.inner(color: .white.opacity(0.10), radius: 1, y: -1))
                )
                .overlay(RoundedRectangle(cornerRadius: 9).fill(.black.opacity(0.16)))
            )
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(.black.opacity(0.35), lineWidth: 0.75))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(.white.opacity(0.22), lineWidth: 1)
                    .mask(LinearGradient(colors: [.clear, .black], startPoint: .center, endPoint: .bottom))
                    .offset(y: 0.6)
            )
    }
}

extension View {
    /// Inlay a control into the wood deck (recessed circular well).
    func woodInlay(size: CGFloat = 40, tone: WoodTone = .oak) -> some View {
        modifier(WoodInlayCircle(size: size, tone: tone))
    }
    /// Inlay a text/grouped control into the wood deck (recessed pill well).
    func woodInlayPill(tone: WoodTone = .oak, hPad: CGFloat = 10, vPad: CGFloat = 6) -> some View {
        modifier(WoodInlayPill(tone: tone, hPad: hPad, vPad: vPad))
    }

    /// Inlay for a KNOB: the wood is bored out to reveal a light metal mounting
    /// plate (the same surface the LED ring was set in before), so the LED reads
    /// on metal instead of appearing to shine through the wood.
    func knobInlay(size: CGFloat, tone: WoodTone = .oak) -> some View {
        self
            .frame(width: size, height: size)
            .background(
                Circle().fill(
                    RadialGradient(colors: [Color(white: 0.965), Color(white: 0.855)],
                                   center: .center, startRadius: 1, endRadius: size * 0.52)
                        .shadow(.inner(color: .black.opacity(0.22), radius: 2, y: 1.2))
                )
            )
            .overlay(Circle().strokeBorder(tone.dark, lineWidth: 2.5))         // bored wood edge
            .overlay(Circle().stroke(.black.opacity(0.30), lineWidth: 0.75))
            .overlay(                                                          // raised wood lip below
                Circle().stroke(.white.opacity(0.22), lineWidth: 1)
                    .mask(LinearGradient(colors: [.clear, .black], startPoint: .center, endPoint: .bottom))
                    .offset(y: 0.6)
            )
    }
}

/// A brushed-metal button cap inlaid into the wood with an LED-backlit function
/// icon. The icon is always shown in its colour (so the button reads its
/// function), and glows when `lit`.
struct InlaidMetalButton: View {
    var system: String
    var lit: Bool = true
    var tint: Color = Theme.orange
    var size: CGFloat = 40
    var tone: WoodTone = .oak

    var body: some View {
        ZStack {
            // brushed metal cap, slightly domed — sits ON the metal mounting plate
            Circle()
                .fill(AngularGradient(
                    colors: [Color(white: 0.93), Color(white: 0.66), Color(white: 0.88),
                             Color(white: 0.62), Color(white: 0.90), Color(white: 0.66), Color(white: 0.93)],
                    center: .center))
                .overlay(Circle().fill(RadialGradient(colors: [.white.opacity(0.6), .clear],
                                                      center: .init(x: 0.38, y: 0.30),
                                                      startRadius: 1, endRadius: size * 0.5)))
                .overlay(Circle().stroke(.black.opacity(0.22), lineWidth: 0.6))
                .frame(width: size * 0.60, height: size * 0.60)
                .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
            // LED function icon
            Image(systemName: system)
                .font(.system(size: size * 0.26, weight: .bold))
                .foregroundStyle(lit ? tint : tint.opacity(0.4))
                .shadow(color: lit ? tint.opacity(0.9) : .clear, radius: lit ? 3.5 : 0)
                .shadow(color: lit ? tint.opacity(0.6) : .clear, radius: lit ? 7 : 0)
        }
        // Metal cap inlaid into a light metal mounting plate, bored into the wood
        // (same treatment as the knobs).
        .knobInlay(size: size, tone: tone)
    }
}

/// Brushed-metal readout pill inlaid into the wood (for text controls — tempo,
/// quantize, bar, preset). Content keeps its own colour so it reads as an LED.
struct MetalInlayPill: ViewModifier {
    var tone: WoodTone = .oak
    var hPad: CGFloat = 9
    var vPad: CGFloat = 7
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, hPad).padding(.vertical, vPad)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.91), Color(white: 0.71)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(.black.opacity(0.18), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.30), radius: 1, y: 0.5)
                    .padding(2)
            )
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tone.dark.opacity(0.96)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(.black.opacity(0.34), lineWidth: 0.75))
    }
}

extension View {
    func metalInlayPill(tone: WoodTone = .oak, hPad: CGFloat = 9, vPad: CGFloat = 7) -> some View {
        modifier(MetalInlayPill(tone: tone, hPad: hPad, vPad: vPad))
    }
}

/// Makes a region read as a screen/display recessed into the metal chassis:
/// rounded, a soft inner top shadow (sunk in), and a dark-top/light-bottom rim.
struct RecessedPanel: ViewModifier {
    var radius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(   // top inner shadow → reads as sunk into the chassis
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.black.opacity(0.32), lineWidth: 4)
                    .blur(radius: 4)
                    .mask(RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center)))
                    .allowsHitTesting(false)
            )
            .overlay(   // machined rim: dark lip up top, catches light at the bottom
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.black.opacity(0.42), .white.opacity(0.5)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
                    .allowsHitTesting(false)
            )
    }
}

extension View {
    func recessedPanel(radius: CGFloat = 14) -> some View { modifier(RecessedPanel(radius: radius)) }
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
/// A ring of discrete LEDs (like the AstroLab's real LED rings) lit up to
/// `progress`, with a bloom on the lit ones. `sweepDeg`/`startDeg` set the arc.
struct SegmentedLEDRing: View {
    var progress: Double
    var color: Color
    var diameter: CGFloat
    var dotRadius: CGFloat
    var segments: Int = 19
    var sweepDeg: Double = 270
    var startDeg: Double = 135    // 0=3 o'clock, +CW; 135 = lower-left
    var bipolar: Bool = false

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = diameter / 2
            let p = max(0, min(1, progress))
            for i in 0..<segments {
                let t = segments > 1 ? Double(i) / Double(segments - 1) : 0
                let lit: Bool = bipolar
                    ? (p >= 0.5 ? (t >= 0.5 - 1e-6 && t <= p + 1e-6) : (t <= 0.5 + 1e-6 && t >= p - 1e-6))
                    : (t <= p + 1e-6)
                let a = (startDeg + sweepDeg * t) * .pi / 180
                let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                if lit {   // bloom
                    let b = dotRadius * 2.4
                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - b, y: pt.y - b, width: b * 2, height: b * 2)),
                             with: .color(color.opacity(0.30)))
                }
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - dotRadius, y: pt.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)),
                         with: .color(lit ? color : color.opacity(0.12)))
                if lit {   // bright core
                    let h = dotRadius * 0.5
                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - h, y: pt.y - h, width: h * 2, height: h * 2)),
                             with: .color(.white.opacity(0.55)))
                }
            }
        }
    }
}

struct LEDRingKnob: View {
    var value: Double
    var range: ClosedRange<Double> = 0...1
    var size: CGFloat = 42
    var ring: Color = Theme.ring       // soft mint LED band, like the AstroLab
    var bipolar: Bool = false          // centered params light from 12 o'clock outward
    var onEditing: (Bool) -> Void = { _ in }   // true when a turn begins, false when it ends
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
        let cap = size - 13
        ZStack {
            // Recessed channel groove the LEDs sit in
            Circle().stroke(LinearGradient(colors: [.black.opacity(0.22), .white.opacity(0.55)],
                                           startPoint: .top, endPoint: .bottom), lineWidth: 4)
                .frame(width: size, height: size)
            if bipolar {
                Capsule().fill(Color.black.opacity(0.22)).frame(width: 1.5, height: 5)
                    .offset(y: -size / 2)
            }
            // Discrete LED ring
            SegmentedLEDRing(progress: shown, color: ring, diameter: size,
                             dotRadius: max(1.3, size * 0.028), segments: 19,
                             sweepDeg: 270, startDeg: 135, bipolar: bipolar)
                .frame(width: size + 14, height: size + 14)
            // Brushed/spun aluminium cap (domed) — soft ambient shadow seats it in the plate
            Circle().fill(Color.black.opacity(0.18)).frame(width: cap + 2, height: cap + 2).blur(radius: 2).offset(y: 1.5)
            Circle()
                .fill(AngularGradient(
                    colors: [Color(white: 0.97), Color(white: 0.72), Color(white: 0.93),
                             Color(white: 0.66), Color(white: 0.95), Color(white: 0.72), Color(white: 0.97)],
                    center: .center))
                .overlay(Circle().fill(RadialGradient(colors: [.white.opacity(0.7), .clear],
                                                      center: .init(x: 0.36, y: 0.30), startRadius: 1, endRadius: size * 0.46)))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.6), .black.opacity(0.28)],
                                                              startPoint: .top, endPoint: .bottom), lineWidth: 1))  // bevel
                .frame(width: cap, height: cap)
            // Engraved indicator notch
            Capsule().fill(Color.black.opacity(0.6))
                .frame(width: 2.2, height: size * 0.18)
                .offset(y: -size * 0.15)
                .rotationEffect(.degrees(-135 + 270 * shown))
                .shadow(color: .white.opacity(0.45), radius: 0.3, y: 0.7)   // engraved light edge
        }
        .frame(width: size + 14, height: size + 14)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if dragStart == nil { dragStart = value; onEditing(true) }
                    let span = range.upperBound - range.lowerBound
                    let nv = min(range.upperBound, max(range.lowerBound,
                        (dragStart ?? value) + Double(-v.translation.height) / 120.0 * span))
                    live = nv; onChange(nv)
                }
                .onEnded { _ in dragStart = nil; live = nil; onEditing(false) }
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
    /// LED-ring level (0…1) — like the AstroLab's screen-encoder ring: shows
    /// browse position while loading sounds, or the param value while turning.
    var progress: Double = 1
    var ringColor: Color = Theme.ring

    var body: some View {
        let screenD = size * 0.74
        ZStack {
            // Brushed-metal bezel ring (the physical rotary)
            Circle()
                .fill(AngularGradient(colors: [Color(white: 0.92), Color(white: 0.66), Color(white: 0.86),
                                               Color(white: 0.62), Color(white: 0.88), Color(white: 0.66), Color(white: 0.92)],
                                      center: .center))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.7), .black.opacity(0.3)],
                                                              startPoint: .top, endPoint: .bottom), lineWidth: 1.2))
                .shadow(color: .black.opacity(0.35), radius: size * 0.05, y: 2)
            // Solid LED bar around the bezel
            let ringD = size * 0.93
            let ringW = max(3, size * 0.05)
            let p = max(0, min(1, progress))
            Circle().stroke(ringColor.opacity(0.16), lineWidth: ringW)
                .frame(width: ringD, height: ringD)
            Circle().trim(from: 0, to: max(0.001, p))
                .stroke(ringColor, style: StrokeStyle(lineWidth: ringW, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: ringD, height: ringD)
                .shadow(color: ringColor.opacity(0.8), radius: size * 0.045)
            // Recessed round screen (dark glass)
            Circle().fill(Color(red: 0.055, green: 0.07, blue: 0.095))
                .frame(width: screenD, height: screenD)
                .overlay(   // vignette — concave glass darkening toward the rim
                    Circle().fill(RadialGradient(colors: [.clear, .black.opacity(0.55)],
                                                 center: .center, startRadius: screenD * 0.18, endRadius: screenD * 0.52)))
                .overlay(Circle().stroke(.black.opacity(0.6), lineWidth: 1.5))   // screen lip
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            // Glass gloss highlight near the top
            Ellipse().fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom))
                .frame(width: screenD * 0.62, height: screenD * 0.34)
                .offset(y: -screenD * 0.22)
                .blur(radius: 1)
            VStack(spacing: size * 0.02) {
                Image(systemName: glyph).font(.system(size: size * 0.16, weight: .semibold))
                    .foregroundStyle(Theme.orange)
                Text(title).font(Theme.mono(size * 0.12, .bold)).foregroundStyle(.white).lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(subtitle).font(Theme.mono(max(7, size * 0.07), .medium)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
            .frame(width: screenD * 0.92)
        }
        .frame(width: size, height: size)
    }
}
