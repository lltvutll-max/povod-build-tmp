import SwiftUI

/// Светлое стекло макета: `.lg` (кнопки, поля) и `.card` (карточки, группы). iOS 26 — Liquid Glass, ниже — материал.
enum GlassKind { case light, card, bar }

private struct GlassFallback<S: Shape>: View {
    let shape: S
    let kind: GlassKind
    var body: some View {
        ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(Pal.surface.opacity(kind == .card ? 0.62 : (kind == .bar ? 0.5 : 0.55)))
            shape.stroke(Pal.surface.opacity(0.95), lineWidth: 0.6)
        }
        .shadow(color: Pal.ink.opacity(kind == .bar ? 0.18 : 0.08), radius: kind == .bar ? 16 : 10, y: kind == .bar ? 12 : 6)
    }
}

extension View {
    @ViewBuilder
    func glass<S: Shape>(_ kind: GlassKind = .light, in shape: S, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            switch kind {
            case .light:
                self.glassEffect(interactive ? Glass.regular.tint(Pal.surface.opacity(0.35)).interactive() : Glass.regular.tint(Pal.surface.opacity(0.35)), in: shape)
            case .card:
                self.glassEffect(Glass.regular.tint(Pal.surface.opacity(0.5)), in: shape)
            case .bar:
                self.glassEffect(Glass.regular.tint(Pal.surface.opacity(0.3)).interactive(), in: shape)
            }
        } else {
            self.background(GlassFallback(shape: shape, kind: kind))
        }
        #else
        self.background(GlassFallback(shape: shape, kind: kind))
        #endif
    }

    func glassCapsule(_ kind: GlassKind = .light, interactive: Bool = false) -> some View {
        glass(kind, in: Capsule(), interactive: interactive)
    }

    func glassRect(_ radius: CGFloat, _ kind: GlassKind = .card) -> some View {
        glass(kind, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Главная кнопка (`.pri`): графитовый градиент, белый текст (в тёмной теме графит светлее, текст тоже белый).
struct PrimaryFill: ViewModifier {
    var radius: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [Color(light: 0x3A3633, dark: 0x5E5853), Color(light: 0x2A2725, dark: 0x47423E)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Color.white.opacity(0.25), lineWidth: 0.6).blendMode(.overlay))
                    .shadow(color: Color.black.opacity(0.22), radius: 10, y: 8)
            )
    }
}

extension View {
    func primaryFill(_ radius: CGFloat = 18) -> some View { modifier(PrimaryFill(radius: radius)) }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(Pal.ink.opacity(configuration.isPressed ? 0.06 : 0))
    }
}

struct GroupRow<Content: View>: View {
    var first = false
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            if !first { Rectangle().fill(Pal.line).frame(height: 0.5) }
            HStack(spacing: 12) { content() }
                .font(Typo.body(16))
                .foregroundStyle(Pal.ink)
                .frame(minHeight: 52)
                .padding(.horizontal, 16)
        }
    }
}

struct Cap: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(Typo.body(13, .semibold))
            .tracking(0.96)
            .foregroundStyle(Pal.fg2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 22)
            .padding(.bottom, 8)
    }
}

struct GlassSwitch: View {
    @Binding var isOn: Bool
    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { isOn.toggle() }
            haptic()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Pal.ink : Pal.ink.opacity(0.15))
                Circle().fill(Pal.surface).frame(width: 28, height: 28).shadow(color: .black.opacity(0.2), radius: 3, y: 2).padding(2)
            }
            .frame(width: 52, height: 32)
            .frame(minWidth: 52, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? AccessibilityTraits([.isButton, .isSelected]) : AccessibilityTraits.isButton)
        .accessibilityValue(isOn ? Text("включено") : Text("выключено"))
    }
}

struct GlassSegment<T: Hashable>: View {
    let items: [(T, String)]
    @Binding var selection: T
    var fontSize: CGFloat = 13
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { i in
                let item = items[i]
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { selection = item.0 }
                    haptic()
                } label: {
                    Text(item.1)
                        .font(Typo.body(fontSize, .semibold))
                        .lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.center)
                        .foregroundStyle(selection == item.0 ? Pal.onInk : Pal.ink)
                        .padding(.horizontal, 2).padding(.vertical, 6)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background {
                            if selection == item.0 {
                                Capsule().fill(Pal.ink).shadow(color: Pal.ink.opacity(0.2), radius: 5, y: 3)
                                    .matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == item.0 ? AccessibilityTraits([.isButton, .isSelected]) : AccessibilityTraits.isButton)
            }
        }
        .padding(3)
        .frame(minHeight: 44)
        .glassCapsule()
    }
}

struct CircleButton: View {
    let system: String
    var size: CGFloat = 44
    var iconSize: CGFloat = 19
    /// подпись для VoiceOver; по умолчанию — по иконке («назад», «закрыть»)
    var label: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: { haptic(); action() }) {
            Image(systemName: system)
                .iconFont(iconSize, .semibold)
                .foregroundStyle(Pal.ink)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .glass(.light, in: Circle(), interactive: true)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(Text(label ?? Self.defaultLabel(system)))
    }
    static func defaultLabel(_ system: String) -> String {
        switch system {
        case "chevron.left": return String(localized: "назад")
        case "xmark": return String(localized: "закрыть")
        default: return system
        }
    }
}

struct PillButton<Label: View>: View {
    var height: CGFloat = 40
    let action: () -> Void
    @ViewBuilder var label: () -> Label
    var body: some View {
        Button(action: { haptic(); action() }) {
            HStack(spacing: 6) { label() }
                .font(Typo.body(14, .semibold))
                .foregroundStyle(Pal.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .frame(minHeight: max(height, 44))
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .glassCapsule(interactive: true)
    }
}

struct Chip: View {
    let text: String
    var count: String? = nil
    var on = false
    var height: CGFloat = 36
    var fontSize: CGFloat = 14
    let action: () -> Void

    var body: some View {
        Button(action: { haptic(); action() }) {
            HStack(spacing: 6) {
                Text(text).font(Typo.body(max(fontSize, 13), .semibold)).lineLimit(1)
                if let count { Text(count).font(Typo.mono(12, .medium)).opacity(0.7) }
            }
            .foregroundStyle(on ? Pal.onInk : Pal.ink)
            .padding(.horizontal, fontSize < 14 ? 11 : 14)
            .padding(.vertical, 4)
            .frame(minHeight: height)
            .background {
                if on { Capsule().fill(Pal.ink).shadow(color: Color.black.opacity(0.18), radius: 6, y: 4) } else { Capsule().fill(Pal.surface.opacity(0.6)) }
            }
            .overlay(Capsule().stroke(Pal.surface.opacity(on ? 0 : 1), lineWidth: 0.5))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(on ? AccessibilityTraits([.isButton, .isSelected]) : AccessibilityTraits.isButton)
    }
}

/// Сила повода: 10 палочек (`.pw`).
struct PowerBar: View {
    let p: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...10, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2).fill(i <= p ? Pal.ink : Pal.ink.opacity(0.12)).frame(width: 5, height: 12)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("шанс ответа \(p) из 10"))
    }
}

struct Bar: View {
    let fraction: Double
    var height: CGFloat = 8
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Pal.ink.opacity(0.1))
                Capsule().fill(Pal.ink).frame(width: max(0, min(1, fraction)) * g.size.width)
            }
        }
        .frame(height: height)
    }
}
