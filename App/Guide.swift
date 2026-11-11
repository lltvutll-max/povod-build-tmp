import SwiftUI
import Network

// Обучение и общие подсказки (11.11.2026, UX-разборы): 4 экрана при первом входе, разовые подсказки на месте,
// пустые экраны с действием, баннер «нет сети». Флаги — в UserDefaults, сброс — «как пользоваться» в настройках.

enum Guide {
    static let onboardedKey = "povod.onboarded.v1"
    /// разовые подсказки на месте
    static let hintLeads = "povod.hint.leads"
    static let hintLead = "povod.hint.lead"
    static let hintHome = "povod.hint.home"
    static let hintMail = "povod.hint.campaigns"
    static let allHints: [String] = [hintLeads, hintLead, hintHome, hintMail]

    /// В снимках CI (-fixture) обучение и подсказки не показываем, иначе они закроют все экраны.
    /// Свои снимки включают их явно: -onboarding / -hints.
    static var onboardingAllowed: Bool {
        let a = ProcessInfo.processInfo.arguments
        return !a.contains("-fixture") || a.contains("-onboarding")
    }
    static var hintsAllowed: Bool {
        let a = ProcessInfo.processInfo.arguments
        return !a.contains("-fixture") || a.contains("-hints")
    }

    /// «как пользоваться»: показать обучение и все подсказки заново
    static func resetAll() {
        let d = UserDefaults.standard
        d.set(false, forKey: onboardedKey)
        for k in allHints { d.set(false, forKey: k) }
    }

    /// Ссылка на веб-кабинет (там подключают почты и создают рассылки).
    static let webCabinet = URL(string: "https://disify.dev/povod/app/")!
    /// «отменить» в тосте держится столько секунд, действие уходит на сервер чуть позже
    static let undoSeconds: Double = 9
    static let undoDelayNs: UInt64 = 9_400_000_000
}

// MARK: - сеть

/// Есть ли сеть (NWPathMonitor). В снимках можно включить «нет сети» аргументом -offline.
@MainActor
@Observable
final class NetMonitor {
    static let shared = NetMonitor()
    var online = true
    private let monitor = NWPathMonitor()

    private init() {
        if ProcessInfo.processInfo.arguments.contains("-offline") {
            online = false
            return
        }
        monitor.pathUpdateHandler = { @Sendable (path: NWPath) in
            let ok: Bool = path.status == .satisfied
            Task { @MainActor in NetMonitor.shared.online = ok }
        }
        monitor.start(queue: DispatchQueue(label: "povod.net"))
    }
}

/// Тонкая плашка сверху на любом экране.
struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash").iconFont(14, .semibold)
            Text("нет сети — показаны сохранённые данные").font(Typo.body(14, .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(light: 0x2A2725, dark: 0x4A4541).opacity(0.94)))
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - обучение при первом входе

struct OnboardingPage: Identifiable {
    let id: Int
    let icon: String
    let title: String
    let text: String
    let points: [String]
}

struct OnboardingView: View {
    let done: () -> Void
    @State private var page = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(id: 0, icon: "building.2", title: String(localized: "компании, которым есть повод написать"),
                       text: String(localized: "Повод находит компании, у которых что-то не так: нет сайта, нельзя записаться онлайн, мало отзывов."),
                       points: [String(localized: "у каждой — готовое первое сообщение под её повод"),
                                String(localized: "«написать» — текст скопируется, а почта или мессенджер откроются сами"),
                                String(localized: "«шанс ответа» — насколько повод весомый для этой компании")]),
        OnboardingPage(id: 1, icon: "folder", title: String(localized: "подборки и папки"),
                       text: String(localized: "Подборка — это поиск: ниша и город, например «кофейни · Казань». Новые компании из неё приходят порциями по тарифу."),
                       points: [String(localized: "каждая подборка — своя папка в «компаниях»"),
                                String(localized: "папки можно объединять и переименовывать"),
                                String(localized: "«фильтр» — статусы, поводы и наличие сайта")]),
        OnboardingPage(id: 2, icon: "envelope", title: String(localized: "почта и рассылки"),
                       text: String(localized: "Ответы компаний приходят во вкладку «почта». Письмо на другом языке переводится само, ваш ответ — тоже."),
                       points: [String(localized: "выберите компании и нажмите «в рассылку» — письма уйдут сами, в рабочие часы"),
                                String(localized: "«мои почты» — ящики, с которых уходят письма"),
                                String(localized: "рассылку можно поставить на паузу в любой момент")]),
        OnboardingPage(id: 3, icon: "bolt", title: String(localized: "сигналы"),
                       text: String(localized: "Сигнал — свежая новость о компании: упал сайт, появились плохие отзывы. Это лучший момент написать первым."),
                       points: [String(localized: "из сигнала можно сразу написать компании"),
                                String(localized: "смахивание по компании: вправо — «связались», влево — «отказ»"),
                                String(localized: "повторить это обучение — «настройки» → «как пользоваться»")]),
    ]

    var body: some View {
        ZStack {
            MetalBackground(star: .corner)
            VStack(spacing: 0) {
                HStack {
                    Text("\(page + 1) из \(pages.count)").font(Typo.mono(13, .medium)).foregroundStyle(Pal.fg2)
                    Spacer()
                    Button(action: finish) {
                        Text("пропустить").font(Typo.body(15, .semibold)).foregroundStyle(Pal.ink)
                            .padding(.horizontal, 10).frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16).padding(.top, 8)
                TabView(selection: $page) {
                    ForEach(pages) { (p: OnboardingPage) in
                        pageView(p).tag(p.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                dots.padding(.bottom, 14)
                Button(action: next) {
                    Text(page == pages.count - 1 ? "начать" : "дальше")
                        .font(Typo.body(17, .semibold))
                        .frame(maxWidth: .infinity).frame(minHeight: 54).primaryFill()
                }
                .buttonStyle(PressStyle())
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
    }

    private func pageView(_ p: OnboardingPage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: p.icon).iconFont(34, .semibold).foregroundStyle(Pal.ink)
                    .frame(width: 72, height: 72)
                    .glass(.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .accessibilityHidden(true)
                Text(p.title).font(Typo.display(26)).tracking(-0.8).foregroundStyle(Pal.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(p.text).font(Typo.body(17)).foregroundStyle(Pal.fg2).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(p.points.indices, id: \.self) { (i: Int) in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: "checkmark").iconFont(13, .bold).foregroundStyle(Pal.ok)
                            Text(p.points[i]).font(Typo.body(16)).foregroundStyle(Pal.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassRect(22)
            }
            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 20)
        }
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(pages) { (p: OnboardingPage) in
                Capsule().fill(p.id == page ? Pal.ink : Pal.ink.opacity(0.2))
                    .frame(width: p.id == page ? 22 : 8, height: 8)
            }
        }
        .animation(.spring(response: 0.3), value: page)
        .accessibilityHidden(true)
    }

    private func next() {
        haptic()
        if page < pages.count - 1 { withAnimation(.spring(response: 0.35)) { page += 1 } } else { finish() }
    }

    private func finish() {
        haptic()
        done()
    }
}

// MARK: - разовая подсказка на месте

/// Карточка-подсказка: показывается один раз (флаг key), закрывается «понятно».
struct HintCard: View {
    let key: String
    let icon: String
    let title: String
    let text: String
    @AppStorage private var seen: Bool

    init(key: String, icon: String, title: String, text: String) {
        self.key = key; self.icon = icon; self.title = title; self.text = text
        _seen = AppStorage(wrappedValue: false, key)
    }

    var body: some View {
        if !seen && Guide.hintsAllowed {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon).iconFont(17, .semibold).foregroundStyle(Pal.ink).padding(.top, 2)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(Typo.body(16, .semibold)).foregroundStyle(Pal.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(text).font(Typo.body(15)).foregroundStyle(Pal.fg2).lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                HStack {
                    Spacer()
                    Button {
                        haptic()
                        withAnimation(.spring(response: 0.3)) { seen = true }
                    } label: {
                        Text("понятно").font(Typo.body(15, .semibold)).foregroundStyle(Pal.onInk)
                            .padding(.horizontal, 18).frame(minHeight: 40)
                            .background(Capsule().fill(Pal.ink))
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassRect(20)
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Pal.ink.opacity(0.18), lineWidth: 1))
            .transition(.opacity.combined(with: .move(edge: .top)))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("подсказка"))
        }
    }
}

// MARK: - пустой экран

/// Пустой экран: что тут будет и что сделать, чтобы стало не пусто.
struct EmptyState: View {
    let icon: String
    let title: String
    let text: String
    var action: String? = nil
    var perform: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).iconFont(28, .semibold).foregroundStyle(Pal.ink.opacity(0.55))
                .accessibilityHidden(true)
            Text(title).font(Typo.body(17, .semibold)).foregroundStyle(Pal.ink).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(text).font(Typo.body(15)).foregroundStyle(Pal.fg2).multilineTextAlignment(.center).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if let action, let perform {
                Button { haptic(); perform() } label: {
                    Text(action).font(Typo.body(16, .semibold))
                        .padding(.horizontal, 22).frame(minHeight: 48).primaryFill(24)
                }
                .buttonStyle(PressStyle())
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}
