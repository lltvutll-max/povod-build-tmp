import SwiftUI

struct SignalsView: View {
    @Environment(Store.self) private var store
    @State private var selected: Signal?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("сигналы").font(Typo.display(28))
                if store.unseenCount > 0 {
                    PillButton(action: store.markAllSeen) { Text("прочитать все") }
                }
                if store.signals.isEmpty && store.firstLoading {
                    SkeletonRows(count: 4, cards: true)
                } else if store.signals.isEmpty {
                    EmptyState(icon: "bolt", title: String(localized: "сигналов пока нет"),
                               text: String(localized: "Сигнал — свежая новость о компании из ваших подборок: упал сайт, появились плохие отзывы. Это лучший момент написать первым. Они придут сами."))
                        .glassRect(24)
                }
                ForEach(store.signals) { signal in
                    SignalCard(signal: signal) {
                        store.markSeen(signal.id)
                        selected = signal
                    }
                }
            }
            .padding(20).padding(.bottom, 90)
        }
        .metalBackground(.corner)
        .foregroundStyle(Pal.ink)
        .refreshable { if !store.fixture { await store.loadSignals() } }
        .task { await store.loadSignals(force: false) }
        .sheet(item: $selected) { SignalSheet(signal: $0) }
    }
}

struct CollectView: View {
    @Environment(Store.self) private var store
    @State private var niche = ""
    @State private var cities = ""
    @State private var limit = 10
    @State private var submitting = false
    @State private var collection: [CollectSeg] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                CircleButton(system: "chevron.left", action: store.pop)
                Text("собрать базу").font(Typo.display(26))
                Text("Подборка — это поиск компаний. Повод найдёт их, проверит сайт и отзывы и подготовит каждой первое сообщение.")
                    .font(Typo.body(15)).foregroundStyle(Pal.fg2).fixedSize(horizontal: false, vertical: true)
                TextField("", text: $niche, prompt: Text("ниша, например: салоны красоты").foregroundColor(Pal.fg3))
                    .font(Typo.body(16)).padding(14).frame(minHeight: 50).glassRect(16)
                    .accessibilityLabel(Text("ниша"))
                TextField("", text: $cities, prompt: Text("города через запятую: Казань, Самара").foregroundColor(Pal.fg3))
                    .font(Typo.body(16)).padding(14).frame(minHeight: 50).glassRect(16)
                    .accessibilityLabel(Text("города"))
                Stepper("компаний на город: \(limit)", value: $limit, in: 1...100).font(Typo.body(16)).padding(14).glassRect(16)
                Button {
                    Task { await submit() }
                } label: {
                    Text(submitting ? "запускаем…" : "начать сбор")
                        .font(Typo.body(17, .semibold))
                        .frame(maxWidth: .infinity).frame(minHeight: 50).primaryFill()
                }
                .buttonStyle(PressStyle())
                .disabled(submitting || niche.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || cityNames.isEmpty)
                if !submitting && (niche.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || cityNames.isEmpty) {
                    Text("чтобы начать, укажите нишу и хотя бы один город").font(Typo.body(13)).foregroundStyle(Pal.fg2)
                }
                ForEach(collection) { segment in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(joinParts([segment.niche, segment.city])).font(Typo.body(15, .semibold))
                        Text(segment.active ? "идёт сбор · найдено \(segment.found)" : "найдено: \(segment.found)")
                            .foregroundStyle(Pal.fg2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14).glassRect(16)
                }
            }
            .padding(20)
        }
        .metalBackground(.corner)
        .foregroundStyle(Pal.ink)
        .task {
            guard !store.fixture else { return }
            while !Task.isCancelled {
                collection = await store.collectStatus()
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
    }

    private var cityNames: [String] {
        cities.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func submit() async {
        guard !submitting else { return }
        submitting = true
        defer { submitting = false }
        if let ids = await store.createSegments(niche: niche.trimmingCharacters(in: .whitespacesAndNewlines), cities: cityNames, limit: limit, contacts: []), !ids.isEmpty {
            store.show(String(localized: "сбор запущен"))
            collection = await store.collectStatus()
        }
    }
}

struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var quietHours = false
    @State private var quietFrom = 21
    @State private var quietTo = 9
    @State private var timezone = TimeZone.current.identifier
    @State private var product = ""
    @State private var productSaved = ""
    @State private var loaded = false
    @State private var inviting = false
    @State private var removing: Manager?
    @State private var confirmLogout = false
    @State private var deleting = false
    /// алерт согласия на перевод писем через ИИ (включение переключателя)
    @State private var askAI = false
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var productFocus: Bool
    @AppStorage(AppTheme.key) private var theme: String = AppTheme.system.rawValue
    @AppStorage(Guide.onboardedKey) private var onboarded = false

    private static let zones: [(String, String)] = [
        ("Europe/Kaliningrad", String(localized: "Калининград")), ("Europe/Moscow", String(localized: "Москва")), ("Europe/Samara", String(localized: "Самара")),
        ("Asia/Yekaterinburg", String(localized: "Екатеринбург")), ("Asia/Omsk", String(localized: "Омск")), ("Asia/Novosibirsk", String(localized: "Новосибирск")),
        ("Asia/Krasnoyarsk", String(localized: "Красноярск")), ("Asia/Irkutsk", String(localized: "Иркутск")), ("Asia/Vladivostok", String(localized: "Владивосток")),
        ("Asia/Tbilisi", String(localized: "Тбилиси")), ("Europe/Istanbul", String(localized: "Стамбул")), ("Europe/Berlin", String(localized: "Берлин")),
        ("Europe/London", String(localized: "Лондон")),
    ]

    private func zoneName(_ id: String) -> String { Self.zones.first { $0.0 == id }?.1 ?? id }
    private func hh(_ h: Int) -> String { String(format: "%02d:00", h) }

    var body: some View {
        let owner = store.user?.isManager != true
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("настройки").font(Typo.display(30)).tracking(-1).foregroundStyle(Pal.ink)
                Text(store.user?.email ?? "").font(Typo.body(15)).foregroundStyle(Pal.fg2).padding(.top, 4)
                if owner {
                    planCard.padding(.top, 18)
                    Cap(String(localized: "что вы продаёте"))
                    productCard
                    Cap(String(localized: "тихие часы"))
                    quietCard
                    Cap(String(localized: "менеджеры"))
                    managersCard
                }
                Cap(String(localized: "оформление")).id("appearance")
                appearanceCard
                Cap(String(localized: "помощь"))
                helpCard
                Cap(String(localized: "почта"))
                aiCard
                Cap(String(localized: "безопасность"))
                VStack(spacing: 0) {
                    GroupRow(first: true) {
                        Image(systemName: "faceid").iconFont(18).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("вход по Face ID")
                            Text(store.faceOn ? "приложение закрывается, когда сворачиваешь" : "выключен").font(Typo.body(13)).foregroundStyle(Pal.fg2)
                        }
                        Spacer()
                        GlassSwitch(isOn: Binding(get: { store.faceOn }, set: { store.requestFace($0) }))
                    }
                }
                .glassRect(24)
                Cap(String(localized: "аккаунт"))
                VStack(spacing: 0) {
                    Button { confirmLogout = true } label: {
                        GroupRow(first: true) {
                            Image(systemName: "rectangle.portrait.and.arrow.right").iconFont(16).frame(width: 24)
                            Text("выйти"); Spacer()
                        }.contentShape(Rectangle())
                    }.buttonStyle(RowPressStyle())
                    // удаление аккаунта (менеджеру — «выйти из команды»): лист DeleteSheet, API /cabinet/account/delete|leave
                    Button { deleting = true } label: {
                        GroupRow {
                            Image(systemName: owner ? "trash" : "person.crop.circle.badge.minus").iconFont(16).frame(width: 24)
                            Text(owner ? "удалить аккаунт" : "выйти из команды"); Spacer()
                        }.foregroundStyle(Pal.danger).contentShape(Rectangle())
                    }.buttonStyle(RowPressStyle())
                }
                .glassRect(24)
            }
            .padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 110)
        }
        .onAppear {
            if store.fixture && store.fixtureMail == "account-delete" { deleting = true }
            if store.fixture && store.fixtureMail == "settings-more" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { proxy.scrollTo("appearance", anchor: .top) }
            }
        }
        }
        .scrollDismissesKeyboard(.interactively)
        .metalBackground(.corner)
        .task {
            // при каждом открытии вкладки не перезапрашиваем: свежее минуты — из памяти, копия с телефона — сразу
            await store.loadSettings(force: false)
            quietHours = store.prefs["quietHours"] as? Bool ?? false
            quietFrom = intOf(store.prefs["quietFrom"]) ?? 21
            quietTo = intOf(store.prefs["quietTo"]) ?? 9
            timezone = store.prefs["timezone"] as? String ?? TimeZone.current.identifier
            product = store.voice["product"] as? String ?? ""
            productSaved = product
            loaded = true
        }
        .onChange(of: quietHours) { _, _ in scheduleSave() }
        .onChange(of: quietFrom) { _, _ in scheduleSave() }
        .onChange(of: quietTo) { _, _ in scheduleSave() }
        .onChange(of: timezone) { _, _ in scheduleSave() }
        .sheet(isPresented: $inviting) { AddManagerSheet() }
        .sheet(isPresented: $deleting) { DeleteSheet() }
        .alert("Убрать менеджера?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), presenting: removing) { manager in
            Button("убрать", role: .destructive) { Task { await store.removeManager(manager) } }
            Button("отмена", role: .cancel) {}
        } message: { m in Text("\(m.name) больше не сможет войти в кабинет. Компании, которые он вёл, останутся.") }
        .alert("Выйти из аккаунта?", isPresented: $confirmLogout) {
            Button("выйти", role: .destructive) { Task { await store.logout() } }
            Button("отмена", role: .cancel) {}
        }
        .alert(Text("Перевод писем через ИИ"), isPresented: $askAI) {
            Button("Разрешить") { store.setAIConsent(true) }
            Button("Не сейчас", role: .cancel) {}
        } message: {
            Text("Для перевода текст писем отправляется в сторонние ИИ-сервисы (Groq). Разрешить?")
        }
    }

    /// перевод писем через ИИ: включить — через алерт согласия, выключить — сразу (согласие отзывается)
    private var aiCard: some View {
        VStack(spacing: 0) {
            GroupRow(first: true) {
                Image(systemName: "globe").iconFont(18).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Перевод писем через ИИ")
                    Text(store.aiConsent ? "текст писем отправляется в Groq" : "выключен — письма в оригинале").font(Typo.body(13)).foregroundStyle(Pal.fg2)
                }
                Spacer()
                GlassSwitch(isOn: aiBinding)
                    .accessibilityLabel(Text("Перевод писем через ИИ"))
            }
        }
        .glassRect(24)
    }

    private var aiBinding: Binding<Bool> {
        Binding<Bool>(get: { store.aiConsent }, set: { (v: Bool) in
            if v { askAI = true } else { store.setAIConsent(false) }
        })
    }

    private func intOf(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let s = v as? String { return Int(s.prefix(2)) }
        if let d = v as? Double { return Int(d) }
        return nil
    }

    /// тихие часы сохраняются сами, через секунду после последнего изменения
    private func scheduleSave() {
        guard loaded else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            if Task.isCancelled { return }
            await store.savePrefs(["quietHours": quietHours, "quietFrom": quietFrom, "quietTo": quietTo, "timezone": timezone])
        }
    }

    /// тема: как в системе / светлая / тёмная
    private var appearanceCard: some View {
        let items: [(String, String)] = AppTheme.allCases.map { (t: AppTheme) -> (String, String) in (t.rawValue, t.title) }
        return VStack(alignment: .leading, spacing: 10) {
            Text("тема приложения").font(Typo.body(16)).foregroundStyle(Pal.ink)
            GlassSegment(items: items, selection: $theme, fontSize: 14)
                .accessibilityLabel(Text("тема приложения"))
            Rectangle().fill(Pal.line).frame(height: 0.5).padding(.top, 4)
            languageRow
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassRect(24)
    }

    /// язык интерфейса: как принято в iOS — системные настройки приложения (там «Язык», если у приложения больше одного языка)
    private var languageRow: some View {
        let code: String = MailLang.mine
        let name: String = Locale(identifier: code).localizedString(forLanguageCode: code) ?? code
        return Button {
            haptic()
            if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "globe").iconFont(17).frame(width: 24).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("язык").font(Typo.body(16)).foregroundStyle(Pal.ink)
                    Text(name).font(Typo.body(13)).foregroundStyle(Pal.fg2)
                    Text("меняется в настройках iPhone: Повод → Язык").font(Typo.body(13)).foregroundStyle(Pal.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right").iconFont(13, .semibold).foregroundStyle(Pal.ink.opacity(0.4)).accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("откроет настройки iPhone для этого приложения"))
    }

    private var helpCard: some View {
        VStack(spacing: 0) {
            Button {
                haptic()
                Guide.resetAll()
                store.tab = .home
                withAnimation(.easeInOut(duration: 0.3)) { onboarded = false }
            } label: {
                GroupRow(first: true) {
                    Image(systemName: "questionmark.circle").iconFont(17).frame(width: 24).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("как пользоваться")
                        Text("короткое обучение и подсказки ещё раз").font(Typo.body(13)).foregroundStyle(Pal.fg2)
                    }
                    .padding(.vertical, 8)
                    Spacer()
                    Image(systemName: "chevron.right").iconFont(13, .semibold).foregroundStyle(Pal.ink.opacity(0.4)).accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            Link(destination: povodSiteURL("support/")) {
                GroupRow {
                    Image(systemName: "questionmark.bubble").iconFont(17).frame(width: 24).accessibilityHidden(true)
                    Text("поддержка")
                    Spacer()
                    Image(systemName: "arrow.up.right").iconFont(13, .semibold).foregroundStyle(Pal.ink.opacity(0.4)).accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            Link(destination: povodSiteURL("legal/privacy/")) {
                GroupRow {
                    Image(systemName: "hand.raised").iconFont(17).frame(width: 24).accessibilityHidden(true)
                    Text("конфиденциальность")
                    Spacer()
                    Image(systemName: "arrow.up.right").iconFont(13, .semibold).foregroundStyle(Pal.ink.opacity(0.4)).accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
        }
        .glassRect(24)
    }

    @ViewBuilder private var planCard: some View {
        let o = store.overview
        let used = o.limits?.leadsUsed ?? 0
        let limit = o.limits?.leads ?? 0
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(o.planName ?? String(localized: "тариф")).font(Typo.display(18)).foregroundStyle(Pal.ink)
                Spacer()
                if let d = o.limits?.daysLeft { Text("ещё \(d) дн.").font(Typo.mono(13, .medium)).foregroundStyle(Pal.fg2) }
            }
            if limit > 0 {
                Bar(fraction: Double(used) / Double(max(limit, 1)))
                Text("компаний в этом периоде: \(used) из \(limit)").font(Typo.body(13)).foregroundStyle(Pal.fg2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassRect(24)
    }

    @ViewBuilder private var productCard: some View {
        let dirty = product.trimmingCharacters(in: .whitespacesAndNewlines) != productSaved.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading, spacing: 10) {
            TextField("", text: $product, prompt: Text("например: сайты с онлайн-записью для клиник").foregroundColor(Pal.fg3), axis: .vertical)
                .lineLimit(2...6)
                .font(Typo.body(16)).foregroundStyle(Pal.ink)
                .focused($productFocus)
            Text("По этому описанию Повод подбирает поводы и пишет первое сообщение.").font(Typo.body(13)).foregroundStyle(Pal.fg2)
            if dirty {
                HStack(spacing: 8) {
                    Button {
                        productFocus = false
                        let t = product
                        Task { await store.saveVoice(["product": t]); productSaved = t }
                    } label: {
                        Text("сохранить").font(Typo.body(14, .semibold)).padding(.horizontal, 18).frame(minHeight: 38).primaryFill(19)
                    }
                    .buttonStyle(PressStyle())
                    Button { product = productSaved; productFocus = false } label: {
                        Text("отмена").font(Typo.body(14, .semibold)).foregroundStyle(Pal.ink).padding(.horizontal, 12).frame(minHeight: 38)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassRect(24)
        .animation(.spring(response: 0.3), value: dirty)
    }

    @ViewBuilder private var quietCard: some View {
        VStack(spacing: 0) {
            GroupRow(first: true) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("не беспокоить ночью")
                    Text("уведомления о сигналах подождут до утра").font(Typo.body(13)).foregroundStyle(Pal.fg2)
                }
                Spacer()
                GlassSwitch(isOn: $quietHours)
            }
            if quietHours {
                GroupRow { Text("с"); Spacer(); hourMenu($quietFrom) }
                GroupRow { Text("до"); Spacer(); hourMenu($quietTo) }
                GroupRow {
                    Text("часовой пояс"); Spacer()
                    Menu {
                        ForEach(Self.zones.indices, id: \.self) { i in Button(Self.zones[i].1) { timezone = Self.zones[i].0 } }
                        if !Self.zones.contains(where: { $0.0 == TimeZone.current.identifier }) {
                            Button("как на телефоне (\(TimeZone.current.identifier))") { timezone = TimeZone.current.identifier }
                        }
                    } label: { menuLabel(zoneName(timezone)) }
                }
            }
        }
        .glassRect(24)
        .animation(.spring(response: 0.3), value: quietHours)
    }

    private func hourMenu(_ value: Binding<Int>) -> some View {
        Menu {
            ForEach(0..<24, id: \.self) { h in Button(hh(h)) { value.wrappedValue = h } }
        } label: { menuLabel(hh(value.wrappedValue)) }
    }

    private func menuLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text).font(Typo.mono(14, .medium))
            Image(systemName: "chevron.up.chevron.down").iconFont(11, .semibold).opacity(0.5)
        }
        .foregroundStyle(Pal.ink)
        .padding(.horizontal, 12).frame(minHeight: 32)
        .background(Capsule().fill(Pal.surface.opacity(0.7)))
    }

    @ViewBuilder private var managersCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.managers.enumerated()), id: \.element.id) { i, m in
                GroupRow(first: i == 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.name).lineLimit(1)
                        Text(m.joined ? m.email : String(localized: "\(m.email) · ещё не вошёл")).font(Typo.body(13)).foregroundStyle(Pal.fg2).lineLimit(1)
                    }
                    Spacer()
                    Button { removing = m } label: {
                        Image(systemName: "minus.circle").iconFont(19).foregroundStyle(Pal.ink.opacity(0.55)).frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("убрать \(m.name)"))
                }
            }
            Button { inviting = true } label: {
                GroupRow(first: store.managers.isEmpty) {
                    Image(systemName: "plus").iconFont(15, .semibold).frame(width: 24)
                    Text("добавить менеджера"); Spacer()
                }.contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
        }
        .glassRect(24)
    }
}

/// Страница сайта Повода на языке приложения: ru — без префикса, en/de/fr/es/pt/it/pl — /povod/<lang>/, остальные — en.
func povodSiteURL(_ path: String) -> URL {
    let lang: String = MailLang.mine
    let known: [String] = ["en", "de", "fr", "es", "pt", "it", "pl"]
    let prefix: String
    if lang == "ru" {
        prefix = ""
    } else if known.contains(lang) {
        prefix = lang + "/"
    } else {
        prefix = "en/"
    }
    let full: String = "https://disify.dev/povod/" + prefix + path
    return URL(string: full) ?? URL(string: "https://disify.dev/povod/")!
}
