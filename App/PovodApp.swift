import SwiftUI
import LocalAuthentication

@main
struct PovodApp: App {
    @State private var store = Store()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppTheme.key) private var theme: String = AppTheme.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme((AppTheme(rawValue: theme) ?? .system).scheme)
                .task { await store.bootstrap() }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        if store.phase == .ready && !store.fixture {
                            // возврат в приложение: свежее минуты не перезапрашиваем, одинаковые запросы не дублируем
                            Task { await store.loadSignals(force: false); await store.loadOverview(force: false) }
                            store.startPolling()
                        }
                    case .background:
                        store.stopPolling()
                        // уход в фон блокирует всегда — даже во время своей проверки Face ID
                        if store.authenticating { store.wentBackground = true }
                        if store.faceOn && store.phase == .ready { store.lock() }
                    case .inactive:
                        // .inactive от системного окна Face ID при включении/выключении — не блокируем
                        if store.faceOn && store.phase == .ready && !store.authenticating { store.lock() }
                    @unknown default: break
                    }
                }
        }
    }
}

struct RootView: View {
    @Environment(Store.self) private var store
    @AppStorage(Guide.onboardedKey) private var onboarded = false

    private var showOnboarding: Bool { store.phase == .ready && !onboarded && Guide.onboardingAllowed && !store.locked }

    var body: some View {
        ZStack {
            Pal.m1.ignoresSafeArea()
            switch store.phase {
            case .launching:
                ZStack { MetalBackground(star: .big); ProgressView().tint(Pal.ink) }.transition(.opacity)
            case .login:
                LoginView().transition(.opacity)
            case .ready:
                MainView().transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
            if showOnboarding {
                OnboardingView { withAnimation(.easeInOut(duration: 0.3)) { onboarded = true } }
                    .transition(.opacity).zIndex(4)
            }
            if store.locked && store.phase == .ready {
                LockView().transition(.opacity).zIndex(5)
            }
            ToastView().zIndex(10)
            if !NetMonitor.shared.online && store.phase != .launching {
                VStack { OfflineBanner().padding(.top, 4); Spacer() }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
                    .zIndex(11)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: store.phase)
        .animation(.easeInOut(duration: 0.25), value: store.locked)
        .animation(.spring(response: 0.4), value: NetMonitor.shared.online)
    }
}

struct MainView: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        ZStack(alignment: .bottom) {
            Group {
                switch store.tab {
                case .home: NavigationStack(path: $store.homePath) { HomeView().destinations() }
                case .leads: NavigationStack(path: $store.leadsPath) { LeadsView().destinations() }
                case .mail: NavigationStack(path: $store.mailPath) { MailView().destinations() }
                case .signals: NavigationStack(path: $store.signalsPath) { SignalsView().destinations() }
                case .settings: NavigationStack(path: $store.settingsPath) { SettingsView().destinations() }
                }
            }
            if store.currentPathEmpty && !(store.tab == .home && store.segSelecting) && !(store.tab == .leads && store.leadSelecting) {
                TabBar().transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.currentPathEmpty)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.segSelecting)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.leadSelecting)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

extension View {
    func destinations() -> some View {
        navigationDestination(for: Route.self) { r in
            Group {
                switch r {
                case .lead(let id): LeadView(leadId: id)
                case .collect: CollectView()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct TabBar: View {
    @Environment(Store.self) private var store
    @Namespace private var ns
    private let items: [(Tab, String, String)] = [
        (.home, "square.grid.2x2", String(localized: "обзор")), (.leads, "building.2", String(localized: "компании")), (.mail, "envelope", String(localized: "почта")),
        (.signals, "bolt", String(localized: "сигналы")), (.settings, "slider.horizontal.3", String(localized: "настройки")),
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { i in
                let item = items[i]
                let on = store.tab == item.0
                Button {
                    if on { withAnimation { store.clearPath(item.0) } } else { withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { store.tab = item.0 } }
                    haptic()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.1).iconFont(20, on ? .semibold : .regular)
                        Text(item.2).font(Typo.body(12, .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .padding(.vertical, 6)
                    .foregroundStyle(on ? Pal.ink : Pal.fg2)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background {
                        if on {
                            Capsule().fill(Pal.surface.opacity(0.92)).shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
                                .matchedGeometryEffect(id: "tab", in: ns)
                        }
                    }
                    .overlay(alignment: .top) {
                        if item.0 == .signals && store.unseenCount > 0 {
                            Text("\(min(99, store.unseenCount))").font(Typo.body(12, .bold)).foregroundStyle(Pal.onInk)
                                .padding(.horizontal, 4).frame(minWidth: 17, minHeight: 17)
                                .background(Capsule().fill(Pal.ink))
                                .offset(x: 12, y: 4)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(item.0 == .signals && store.unseenCount > 0 ? String(localized: "\(item.2), новых: \(store.unseenCount)") : item.2))
                .accessibilityAddTraits(on ? AccessibilityTraits([.isButton, .isSelected]) : AccessibilityTraits.isButton)
                .accessibilityShowsLargeContentViewer {
                    Label(item.2, systemImage: item.1)
                }
            }
        }
        .padding(4)
        .frame(minHeight: 64)
        .fixedSize(horizontal: false, vertical: true)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .glass(.bar, in: Capsule())
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }
}

struct ToastView: View {
    @Environment(Store.self) private var store
    var body: some View {
        VStack {
            Spacer()
            if let t = store.toast, !store.locked {
                HStack(spacing: 8) {
                    Image(systemName: t.ok ? "checkmark" : "exclamationmark.circle").iconFont(15, .bold)
                        .foregroundStyle(t.ok ? Color(hex: 0x9FE3BF) : Color(hex: 0xFFB8B0))
                        .accessibilityHidden(true)
                    Text(t.text).font(Typo.body(15)).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if let undo = t.undo {
                        Button {
                            haptic()
                            withAnimation { store.toast = nil }
                            undo()
                        } label: {
                            Text("отменить").font(Typo.body(16, .semibold)).foregroundStyle(Color(hex: 0x9FE3BF))
                                .padding(.horizontal, 12).frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(light: 0x2A2725, dark: 0x45403C).opacity(0.95)))
                .padding(.horizontal, 12)
                .padding(.bottom, 96)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(t.id)
                .onTapGesture { withAnimation { store.toast = nil } }
            }
        }
        .allowsHitTesting(store.toast != nil)
    }
}

struct LockView: View {
    @Environment(Store.self) private var store
    @State private var message: String?
    @State private var busy = false

    var body: some View {
        ZStack {
            MetalBackground(star: .big)
            VStack(spacing: 16) {
                Spacer()
                StarLogo(size: 22)
                if let message { Text(message).font(Typo.body(14)).foregroundStyle(Pal.fg2).multilineTextAlignment(.center).padding(.horizontal, 30) }
                Button { unlock() } label: {
                    Label("войти по Face ID", systemImage: "faceid").font(Typo.body(16, .semibold)).frame(maxWidth: 260).frame(minHeight: 52).primaryFill()
                }
                .buttonStyle(PressStyle())
                .disabled(busy)
                Button { Task { await store.logout() } } label: {
                    Text("войти заново (выйти из кабинета)").font(Typo.body(15, .medium)).foregroundStyle(Pal.ink).frame(minHeight: 44)
                }
                Spacer().frame(height: 60)
            }
        }
        .onAppear { unlock() }
    }

    private func unlock() {
        guard !busy else { return }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            message = String(localized: "Face ID и код-пароль недоступны на этом телефоне. Войди заново по почте.")
            return
        }
        busy = true
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "Вход в кабинет Повода")) { ok, _ in
            Task { @MainActor in
                busy = false
                if ok { store.locked = false } else { message = String(localized: "не получилось подтвердить — попробуй ещё раз") }
            }
        }
    }
}

/// Звезда + «повод» (логотип в шапке).
struct StarLogo: View {
    var size: CGFloat = 18
    var body: some View {
        HStack(spacing: 8) {
            StarShape().fill(Pal.ink).frame(width: size, height: size)
            Text(String(localized: "logo.povod", defaultValue: "повод")).font(Typo.display(size, .bold)).tracking(-0.6).foregroundStyle(Pal.ink)
        }
    }
}

/// Восьмилучевая звезда из логотипа (тот же контур, что в макете).
struct StarShape: Shape {
    func path(in r: CGRect) -> Path {
        let pts: [(CGFloat, CGFloat)] = [
            (1638.24, 997.219), (1216.71, 1091.4), (1447.93, 1456.42), (1083.57, 1225.19), (988.738, 1646.72), (893.911, 1225.19),
            (529.542, 1456.42), (760.764, 1091.4), (339.238, 997.219), (760.764, 903.042), (529.542, 538.023), (893.911, 769.245),
            (988.738, 347.719), (1083.57, 769.245), (1447.93, 538.023), (1216.71, 903.042),
        ]
        var p = Path()
        for (i, pt) in pts.enumerated() {
            let x = r.minX + (pt.0 - 339) / 1300 * r.width
            let y = r.minY + (pt.1 - 347) / 1300 * r.height
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        p.closeSubpath()
        return p
    }
}

extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
