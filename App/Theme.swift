import SwiftUI
import UIKit

// Токены утверждённого макета Повода (povod-demo-template.html, :root): светлый металлик, графит, без красного.
// С 11.11.2026 у каждого токена есть тёмный вариант: тема — системная / светлая / тёмная (настройки → оформление).
enum Pal {
    static let ink = Color(light: 0x2A2725, dark: 0xECE9E4)
    static let fg2 = Color(light: 0x5F5B57, dark: 0xB8B3AD)
    /// вторичный серый — темнее прежнего 0x7A7672 (контраст ≥4.5:1 на m0)
    static let fg3 = Color(light: 0x66625E, dark: 0x9C978F)
    static let ok = Color(light: 0x1F7A4D, dark: 0x5CC48E)
    static let m0 = Color(light: 0xF7F6F2, dark: 0x22201E)
    static let m1 = Color(light: 0xECEAE5, dark: 0x1A1918)
    static let m2 = Color(light: 0xDEDBD5, dark: 0x121110)
    static let line = Color(light: 0x2A2725, dark: 0xECE9E4, alpha: 0.12)
    static let card = Color(light: 0xFFFFFF, dark: 0x2E2C29, alpha: 0.62)
    static let unseen = ink
    static let seen = Color(light: 0x7E7B76, dark: 0x8F8A84)
    /// светлая подложка карточек/полей (в тёмной теме — графит)
    static let surface = Color(light: 0xFFFFFF, dark: 0x2E2C29)
    /// текст и иконки на заливке `ink` (чип «вкл», бейдж, кнопка отправки)
    static let onInk = Color(light: 0xFFFFFF, dark: 0x1A1918)
    /// удалить / ошибка
    static let danger = Color(light: 0x9A2A1E, dark: 0xFF8E7E)
}

/// Тема приложения: как в системе / светлая / тёмная (UserDefaults «povod.theme»).
enum AppTheme: String, CaseIterable {
    case system, light, dark
    var title: String {
        switch self {
        case .system: return String(localized: "как в системе")
        case .light: return String(localized: "светлая")
        case .dark: return String(localized: "тёмная")
        }
    }
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    static let key = "povod.theme"
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
    /// цвет, который сам меняется под светлую/тёмную тему
    init(light: UInt32, dark: UInt32, alpha: Double = 1) {
        self.init(uiColor: UIColor { (t: UITraitCollection) -> UIColor in
            let hex: UInt32 = t.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: CGFloat(alpha))
        })
    }
}

/// Иконка SF Symbols, которая растёт вместе с системным размером текста (не больше чем в 1,6 раза).
struct IconFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let base: CGFloat
    private let weight: Font.Weight
    init(_ size: CGFloat, _ weight: Font.Weight) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
        base = size
        self.weight = weight
    }
    func body(content: Content) -> some View {
        content.font(.system(size: min(size, base * 1.6), weight: weight))
    }
}

extension View {
    func iconFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> some View { modifier(IconFont(size, weight)) }
}

enum Typo {
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "Unbounded-Bold"
        case .medium, .regular, .light: name = "Unbounded-Medium"
        default: name = "Unbounded-SemiBold"
        }
        return .custom(name, size: size)
    }

    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "Onest-Bold"
        case .semibold: name = "Onest-SemiBold"
        case .medium: name = "Onest-Medium"
        default: name = "Onest-Regular"
        }
        return .custom(name, size: size)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .custom(weight == .medium || weight == .regular ? "JetBrainsMono-Medium" : "JetBrainsMono-SemiBold", size: size)
    }
}

func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
    UIImpactFeedbackGenerator(style: style).impactOccurred()
}

/// Первая буква заглавная (города в данных — строчными).
func capFirst(_ s: String) -> String {
    guard let f = s.first else { return s }
    return f.uppercased() + s.dropFirst()
}

/// Фон экрана: металлик (два радиальных блика + вертикальный перелив m0→m1→m2) и серебряная звезда.
struct MetalBackground: View {
    var star: StarMode = .corner
    enum StarMode { case none, corner, big }
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                LinearGradient(stops: [.init(color: Pal.m0, location: 0), .init(color: Pal.m1, location: 0.55), .init(color: Pal.m2, location: 1)],
                               startPoint: UnitPoint(x: 0.4, y: 0), endPoint: UnitPoint(x: 0.6, y: 1))
                RadialGradient(colors: [Pal.surface.opacity(0.7), .clear], center: UnitPoint(x: 0.9, y: 0.06), startRadius: 0, endRadius: geo.size.width * 0.75)
                RadialGradient(colors: [Color(light: 0x8A8782, dark: 0x000000, alpha: 0.4), .clear], center: UnitPoint(x: 0, y: 1), startRadius: 0, endRadius: geo.size.width * 0.9)
                if star != .none {
                    Image("Star")
                        .resizable()
                        .scaledToFit()
                        .frame(width: star == .big ? 440 : 300, height: star == .big ? 440 : 300)
                        .opacity(scheme == .dark ? 0.3 : 1)
                        .shadow(color: Color.black.opacity(0.22), radius: 20, y: 24)
                        .offset(x: star == .big ? 25 : 90, y: star == .big ? 40 : -50)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topTrailing)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

extension View {
    func metalBackground(_ star: MetalBackground.StarMode = .corner) -> some View {
        background(MetalBackground(star: star))
    }
}
