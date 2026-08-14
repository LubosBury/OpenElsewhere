import SwiftUI

/// The OpenElsewhere design system, ported from the handoff bundle's token
/// stylesheets (`colors.css`, `typography.css`, `spacing.css`, `effects.css`).
///
/// Dark is the canonical theme. The light values are the
/// `:root[data-theme="light"]` overrides, verbatim; where a token has no light
/// override (the semantic hues) the dark value is reused, as CSS inheritance
/// would.
///
/// Every view reads tokens through `OETheme.resolve(colorScheme)` rather than
/// hardcoding a colour, so a token change lands everywhere at once.

// MARK: - Colour helper

extension Color {
    /// A hex literal exactly as written in `colors.css` (`0xRRGGBB`).
    init(oeHex hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

// MARK: - Theme

struct OETheme {
    let accent: Color
    let accentSoft: Color
    let accentLine: Color

    let warn: Color
    let warnSoft: Color
    let warnLine: Color

    let danger: Color
    let ok: Color
    let sponsor: Color
    let sponsorSoft: Color
    let sponsorLine: Color

    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    /// Label colour on top of a filled accent surface.
    let textOnAccent: Color

    let surfaceCard: Color
    let surfaceCardRaised: Color
    let surfaceInset: Color
    let surfaceControl: Color
    let surfaceMenu: Color

    let borderHairline: Color
    let borderInset: Color

    let backgroundFrom: Color
    let backgroundTo: Color

    let shadowCard: Color
    let shadowMenu: Color

    /// The prototype exposes `glowLevel` as a multiplier and was reviewed at
    /// 55 %. Neon on a light background reads as smudge rather than glow, so
    /// light mode runs at a fraction of that.
    let glowScale: CGFloat

    /// Strength of the two accent blooms behind the window gradient. Same
    /// reasoning as `glowScale`: what reads as depth on navy reads as a stain
    /// on near-white.
    let bloomOpacity: Double

    static let dark = OETheme(
        accent: Color(oeHex: 0x73AEFF),
        accentSoft: Color(oeHex: 0x73AEFF, opacity: 0.18),
        accentLine: Color(oeHex: 0x73AEFF, opacity: 0.35),

        warn: Color(oeHex: 0xFF9F0A),
        warnSoft: Color(oeHex: 0xFF9F0A, opacity: 0.16),
        warnLine: Color(oeHex: 0xFF9F0A, opacity: 0.38),

        danger: Color(oeHex: 0xFF6B6B),
        ok: Color(oeHex: 0x32D6A0),
        sponsor: Color(oeHex: 0xFFD60A),
        sponsorSoft: Color(oeHex: 0xFFD60A, opacity: 0.16),
        sponsorLine: Color(oeHex: 0xFFD60A, opacity: 0.35),

        textPrimary: .white.opacity(0.95),
        textSecondary: .white.opacity(0.60),
        textTertiary: .white.opacity(0.38),
        textOnAccent: Color(oeHex: 0x070B1A),

        surfaceCard: .white.opacity(0.07),
        surfaceCardRaised: .white.opacity(0.10),
        surfaceInset: .white.opacity(0.05),
        surfaceControl: .white.opacity(0.08),
        surfaceMenu: Color(oeHex: 0x121830, opacity: 0.72),

        borderHairline: .white.opacity(0.10),
        borderInset: .white.opacity(0.08),

        backgroundFrom: Color(oeHex: 0x0D142E),
        backgroundTo: Color(oeHex: 0x141F47),

        shadowCard: .black.opacity(0.30),
        shadowMenu: .black.opacity(0.45),

        glowScale: 0.55,
        bloomOpacity: 0.20
    )

    static let light = OETheme(
        accent: Color(oeHex: 0x3373F2),
        accentSoft: Color(oeHex: 0x3373F2, opacity: 0.12),
        accentLine: Color(oeHex: 0x3373F2, opacity: 0.35),

        warn: Color(oeHex: 0xFF9F0A),
        warnSoft: Color(oeHex: 0xFF9F0A, opacity: 0.16),
        warnLine: Color(oeHex: 0xFF9F0A, opacity: 0.38),

        danger: Color(oeHex: 0xFF6B6B),
        ok: Color(oeHex: 0x32D6A0),
        sponsor: Color(oeHex: 0xFFD60A),
        sponsorSoft: Color(oeHex: 0xFFD60A, opacity: 0.22),
        sponsorLine: Color(oeHex: 0xFFD60A, opacity: 0.45),

        textPrimary: Color(oeHex: 0x0A0E1C, opacity: 0.92),
        textSecondary: Color(oeHex: 0x0A0E1C, opacity: 0.55),
        textTertiary: Color(oeHex: 0x0A0E1C, opacity: 0.35),
        textOnAccent: .white,

        surfaceCard: .white.opacity(0.62),
        surfaceCardRaised: .white.opacity(0.78),
        surfaceInset: .white.opacity(0.55),
        surfaceControl: .white.opacity(0.70),
        surfaceMenu: Color(oeHex: 0xFAFCFF, opacity: 0.82),

        borderHairline: Color(oeHex: 0x0A0E1C, opacity: 0.05),
        borderInset: Color(oeHex: 0x0A0E1C, opacity: 0.07),

        backgroundFrom: Color(oeHex: 0xE0EDFF),
        backgroundTo: Color(oeHex: 0xF2F7FF),

        shadowCard: Color(oeHex: 0x0A0E1C, opacity: 0.06),
        shadowMenu: Color(oeHex: 0x0A0E1C, opacity: 0.18),

        glowScale: 0.18,
        bloomOpacity: 0.07
    )

    static func resolve(_ scheme: ColorScheme) -> OETheme {
        scheme == .dark ? .dark : .light
    }
}

// MARK: - Tone

/// The two banner / button tones in the system. A tone bundles a solid fill,
/// its tint, its hairline, and the label colour that stays legible on it.
enum OETone {
    case accent
    case warn

    func solid(_ t: OETheme) -> Color { self == .accent ? t.accent : t.warn }
    func tint(_ t: OETheme) -> Color { self == .accent ? t.accentSoft : t.warnSoft }
    func line(_ t: OETheme) -> Color { self == .accent ? t.accentLine : t.warnLine }

    /// Navy on orange in both themes — the warn hue never darkens enough for
    /// white to pass, so it does not follow `textOnAccent`.
    func onSolid(_ t: OETheme) -> Color {
        self == .accent ? t.textOnAccent : Color(oeHex: 0x070B1A)
    }
}

// MARK: - Spacing, radii, motion

enum OE {
    static let hairline: CGFloat = 0.5

    enum Radius {
        static let chip: CGFloat = 10
        static let control: CGFloat = 8
        static let row: CGFloat = 12
        static let tile: CGFloat = 16
        static let banner: CGFloat = 16
        static let card: CGFloat = 20
        static let menuRow: CGFloat = 9
    }

    enum Pad {
        static let window: CGFloat = 20
        static let banner: CGFloat = 16
        static let rowX: CGFloat = 16
        static let rowY: CGFloat = 14
    }

    enum Size {
        static let settingsMinWidth: CGFloat = 620
        static let contentMinHeight: CGFloat = 290
        static let menuWidth: CGFloat = 320
        static let onboardingWidth: CGFloat = 420
    }

    /// `cubic-bezier(0.34,1.36,0.64,1)` from `--ease-spring`.
    static let spring = Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let springTight = Animation.spring(response: 0.35, dampingFraction: 0.85)
    /// `--dur-fast` / `--dur-base` on `--ease-out`.
    static let easeFast = Animation.easeOut(duration: 0.12)
    static let easeBase = Animation.easeOut(duration: 0.2)
}

// MARK: - Typography

/// The prototype substitutes JetBrains Mono for the label face and IBM Plex
/// Sans for prose. Per the handoff, the label face maps to
/// `.system(design: .rounded)` and prose to the default system face.
enum OEFont {
    static let appName = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let appSubtitle = Font.system(size: 12)
    static let onboardingTitle = Font.system(size: 18, weight: .semibold, design: .rounded)
    static let onboardingBody = Font.system(size: 12.5)

    static let tab = Font.system(size: 11, weight: .medium, design: .rounded)
    static let eyebrow = Font.system(size: 10, weight: .semibold, design: .rounded)
    static let switchLabel = Font.system(size: 10, weight: .semibold, design: .rounded)

    static let rowTitle = Font.system(size: 13, weight: .medium)
    static let rowSubtitle = Font.system(size: 11.5)
    static let bannerTitle = Font.system(size: 13, weight: .semibold)
    static let bannerBody = Font.system(size: 11.5)

    static let button = Font.system(size: 11, weight: .semibold, design: .rounded)
    static let buttonLarge = Font.system(size: 12, weight: .semibold, design: .rounded)
    static let link = Font.system(size: 11.5)
    static let hint = Font.system(size: 10, design: .rounded)

    static let sentence = Font.system(size: 13)
    static let sentenceValue = Font.system(size: 13, weight: .medium)
    static let menuRow = Font.system(size: 12.5)
    static let shortcut = Font.system(size: 11, design: .rounded)
    static let code = Font.system(size: 11, design: .monospaced)

    /// `--tracking-label` (0.06em) resolved to points at a given size.
    static func labelTracking(_ size: CGFloat) -> CGFloat { size * 0.06 }
    /// `--tracking-caps` (0.14em) resolved to points at a given size.
    static func capsTracking(_ size: CGFloat) -> CGFloat { size * 0.14 }
}

// MARK: - Effects

extension View {
    /// A `--glow-*` token. CSS blur radii are roughly twice a SwiftUI shadow
    /// radius, so the token's px value is halved before the `glowScale`
    /// multiplier is applied.
    func oeGlow(_ color: Color, css: CGFloat, scale: CGFloat) -> some View {
        shadow(color: color, radius: css * scale / 2)
    }

    /// Fill + hairline in one call — the shape every surface in the system uses.
    func oeSurface(_ fill: Color,
                   border: Color,
                   radius: CGFloat,
                   borderWidth: CGFloat = OE.hairline) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(border, lineWidth: borderWidth)
        )
    }

    /// A row in the General / About tabs: `--surface-inset` + `--border-inset`.
    func oeInsetRow(_ t: OETheme) -> some View {
        padding(.horizontal, OE.Pad.rowX)
            .padding(.vertical, OE.Pad.rowY)
            .oeSurface(t.surfaceInset, border: t.borderInset, radius: OE.Radius.row)
    }
}

/// Full-bleed window background: the `--bg-app` gradient with the prototype's
/// two accent bloom fields over it.
struct OEBackground: View {
    let theme: OETheme

    var body: some View {
        LinearGradient(colors: [theme.backgroundFrom, theme.backgroundTo],
                       startPoint: .topLeading,
                       endPoint: .bottomTrailing)
        .overlay(alignment: .topLeading) {
            RadialGradient(colors: [theme.accent.opacity(theme.bloomOpacity), .clear],
                           center: .center, startRadius: 0, endRadius: 380)
            .frame(width: 760, height: 520)
            .offset(x: -180, y: -180)
        }
        .overlay(alignment: .bottomTrailing) {
            RadialGradient(colors: [theme.accent.opacity(theme.bloomOpacity * 0.8), .clear],
                           center: .center, startRadius: 0, endRadius: 340)
            .frame(width: 680, height: 460)
            .offset(x: 160, y: 150)
        }
        .clipped()
        .ignoresSafeArea()
    }
}

/// Hairline rule, `--border-hairline` at 0.5 pt.
struct OEHairline: View {
    let theme: OETheme
    var body: some View {
        Rectangle()
            .fill(theme.borderHairline)
            .frame(height: OE.hairline)
    }
}

// MARK: - Eyebrow

/// 10 pt uppercase tertiary section label.
struct OEEyebrow: View {
    let text: String
    let theme: OETheme

    var body: some View {
        Text(text)
            .font(OEFont.eyebrow)
            .tracking(OEFont.capsTracking(10))
            .textCase(.uppercase)
            .foregroundStyle(theme.textTertiary)
    }
}

// MARK: - Switch

/// The pill switch from the prototype. Implemented as a `ToggleStyle` so the
/// label and track stay one hit target and `Toggle`'s accessibility is kept.
///
/// A style struct is not a `View`, so SwiftUI does not install dynamic
/// properties declared on it — `@Environment` there would silently read a
/// default. Every style in this file therefore does its work in a nested
/// `Body` view, which is a real view and gets a real environment.
struct OESwitchStyle: ToggleStyle {
    var width: CGFloat = 44
    var height: CGFloat = 26
    var knob: CGFloat = 20
    var glows = true
    var labelGap: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration,
             width: width, height: height, knob: knob,
             glows: glows, labelGap: labelGap)
    }

    struct StyledBody: View {
        let configuration: Configuration
        let width: CGFloat
        let height: CGFloat
        let knob: CGFloat
        let glows: Bool
        let labelGap: CGFloat

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            let t = OETheme.resolve(scheme)
            let inset = (height - knob) / 2
            let travel = width - knob - inset * 2

            return HStack(spacing: labelGap) {
                configuration.label
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(configuration.isOn ? t.accent : t.surfaceControl)
                        .overlay(Capsule().strokeBorder(t.borderHairline, lineWidth: OE.hairline))
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                        .frame(width: knob, height: knob)
                        .offset(x: inset + (configuration.isOn ? travel : 0))
                }
                .frame(width: width, height: height)
                .oeGlow(configuration.isOn && glows ? t.accentLine : .clear,
                        css: 26, scale: t.glowScale)
                .animation(OE.easeBase, value: configuration.isOn)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(OE.spring) { configuration.isOn.toggle() }
            }
        }
    }
}

// MARK: - Buttons

/// Filled tone button — the setup strip CTA and the onboarding primary.
struct OEFilledButtonStyle: ButtonStyle {
    var tone: OETone = .accent
    var font: Font = OEFont.button
    var fontSize: CGFloat = 11
    var horizontalPadding: CGFloat = 14
    var verticalPadding: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, tone: tone, font: font, fontSize: fontSize,
             horizontalPadding: horizontalPadding, verticalPadding: verticalPadding)
    }

    struct StyledBody: View {
        let configuration: Configuration
        let tone: OETone
        let font: Font
        let fontSize: CGFloat
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            let t = OETheme.resolve(scheme)
            return configuration.label
                .font(font)
                .tracking(OEFont.labelTracking(fontSize))
                .foregroundStyle(tone.onSolid(t))
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .oeSurface(tone.solid(t), border: tone.line(t), radius: OE.Radius.chip)
                .oeGlow(tone.line(t), css: 22, scale: t.glowScale)
                .opacity(configuration.isPressed ? 0.8 : 1)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(OE.easeFast, value: configuration.isPressed)
        }
    }
}

/// Tinted button — accent-soft fill, accent hairline, accent label.
struct OESoftButtonStyle: ButtonStyle {
    var tone: OETone = .accent
    var glows = false
    var horizontalPadding: CGFloat = 13
    var verticalPadding: CGFloat = 7

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, tone: tone, glows: glows,
             horizontalPadding: horizontalPadding, verticalPadding: verticalPadding)
    }

    struct StyledBody: View {
        let configuration: Configuration
        let tone: OETone
        let glows: Bool
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            let t = OETheme.resolve(scheme)
            return configuration.label
                .font(OEFont.button)
                .tracking(OEFont.labelTracking(11))
                .foregroundStyle(tone.solid(t))
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .oeSurface(tone.tint(t), border: tone.line(t), radius: OE.Radius.chip)
                .oeGlow(glows ? tone.line(t) : .clear, css: 20, scale: t.glowScale)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .animation(OE.easeFast, value: configuration.isPressed)
        }
    }
}

/// Neutral chip — `--surface-control` fill, primary label. Used for the
/// sponsor tip prices and the helper-sheet actions.
struct OEChipButtonStyle: ButtonStyle {
    var fill: Color?
    var border: Color?

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, fill: fill, border: border)
    }

    struct StyledBody: View {
        let configuration: Configuration
        let fill: Color?
        let border: Color?

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            let t = OETheme.resolve(scheme)
            return configuration.label
                .font(OEFont.button)
                .foregroundStyle(t.textPrimary)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .oeSurface(fill ?? t.surfaceControl,
                           border: border ?? t.borderHairline,
                           radius: 9)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .animation(OE.easeFast, value: configuration.isPressed)
        }
    }
}

/// Quiet text button — "Skip for now", the rule delete glyph.
struct OETextButtonStyle: ButtonStyle {
    var font: Font = OEFont.link
    var color: Color?
    var hoverColor: Color?

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, font: font, color: color, hoverColor: hoverColor)
    }

    struct StyledBody: View {
        let configuration: Configuration
        let font: Font
        let color: Color?
        let hoverColor: Color?

        @State private var hovering = false
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            let t = OETheme.resolve(scheme)
            let base = color ?? t.textTertiary
            return configuration.label
                .font(font)
                .foregroundStyle(hovering ? (hoverColor ?? t.textSecondary) : base)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .opacity(configuration.isPressed ? 0.6 : 1)
                .onHover { hovering = $0 }
                .animation(OE.easeFast, value: hovering)
        }
    }
}

// MARK: - Chip menu

/// A pop-up menu drawn as a system chip rather than a `Picker`. `Picker`'s
/// macOS bezel cannot be restyled to `--surface-control` + hairline + radius 8,
/// and the rule sentence depends on the picker reading as light inline text.
struct OEChipMenu<Content: View>: View {
    let title: String
    var icon: NSImage?
    var font: Font = OEFont.sentenceValue
    var maxTitleWidth: CGFloat = 190
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = OETheme.resolve(scheme)
        Menu {
            content()
        } label: {
            HStack(spacing: 6) {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 14, height: 14)
                }
                Text(title)
                    .font(font)
                    .foregroundStyle(t.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: maxTitleWidth, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(t.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .oeSurface(t.surfaceControl, border: t.borderHairline, radius: OE.Radius.control)
            .contentShape(Rectangle())
        }
        // `.borderlessButton` draws its own label and indicator and discards
        // the chip styling entirely. `.button` + `.plain` is the combination
        // that renders the label exactly as given, with no bezel.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// One row inside an `OEChipMenu`: app icon plus name, with a checkmark for
/// the current selection. `Menu` content does not lay out arbitrary `HStack`s
/// reliably, so the icon rides along as an inline `Image` in a single `Text`.
struct OEMenuRowLabel: View {
    let name: String
    let icon: NSImage?

    var body: some View {
        if let icon {
            Label {
                Text(name)
            } icon: {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            }
        } else {
            Text(name)
        }
    }
}

// MARK: - App icon

/// The app's own icon, used for the header tile and the empty state.
enum OEAppIcon {
    /// Read straight out of the bundle rather than via
    /// `NSApplication.applicationIconImage`, which returns the generic
    /// placeholder — a blank tile — whenever LaunchServices has not caught up
    /// with the running copy. That happens routinely during development and
    /// for a freshly installed build, and there is no way to tell the
    /// placeholder from a real icon after the fact.
    static let image: NSImage? = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            return icon
        }
        return NSImage(named: "AppIcon")
    }()
}

/// The app mark. Falls back to the vector compass when the bundle carries no
/// icon, so the tile never renders empty.
struct OEAppIconView: View {
    var size: CGFloat
    var tint: Color

    var body: some View {
        if let icon = OEAppIcon.image {
            Image(nsImage: icon)
                .resizable()
                .frame(width: size, height: size)
        } else {
            CompassLogo(size: size, tint: tint)
        }
    }
}

// MARK: - Window access

/// Reaches the `NSWindow` hosting a SwiftUI scene, for the handful of window
/// properties SwiftUI does not expose.
struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // `view.window` is nil until the view is in the hierarchy.
        DispatchQueue.main.async {
            if let window = view.window { configure(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
