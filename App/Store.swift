import Foundation
import Observation
import SwiftUI
import LocalAuthentication
import UserNotifications

enum Phase { case launching, login, ready }
enum Tab: String, CaseIterable { case home, leads, mail, signals, settings }

enum Route: Hashable {
    case lead(Int)
    case collect
}

struct Toast: Equatable {
    let id = UUID()
    let text: String
    let ok: Bool
    /// «отменить» прямо в тосте (смена статуса и т. п.)
    var undo: (() -> Void)? = nil
    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

/// Состояние приложения: живые данные кабинета Повода через его REST API, локально — только «прочитанные» сигналы и настройки телефона.
@MainActor
@Observable
final class Store {
    var phase: Phase = .launching
    var user: User?
    var overview = Overview()
    var segments: [Segment] = []
    var leads: [Lead] = []
    var leadsTotal = 0
    var signals: [Signal] = []
    var managers: [Manager] = []
    var prefs: [String: Any] = [:]
    var voice: [String: Any] = [:]
    var toast: Toast?
    var loading = false
    var lastError: String?
    var tab: Tab = .home
    var homePath: [Route] = []
    var leadsPath: [Route] = []
    var mailPath: [Route] = []
    var signalsPath: [Route] = []
    var settingsPath: [Route] = []
    var leadFilter = "new"
    var segmentFilter: Segment?
    var locked = false
    /// идёт своя проверка Face ID (включить/выключить) — системное окно уводит сцену в .inactive, блокировать нельзя
    var authenticating = false
    /// за время проверки приложение уходило в фон — замок после неё не снимаем
    var wentBackground = false
    var fixture = false
    /// для снимков CI: открыть в почте переписку или новое письмо
    var fixtureMail: String?
    /// папки лидов (Folders.swift), по аккаунту
    let folders = FolderStore()
    /// почта (MailViews.swift): живёт здесь, а не в экране — при переключении вкладок не пересоздаётся и не грузится заново
    let mail = MailStore()
    /// одна загрузка за раз по ключу и «свежесть» данных (Cache.swift)
    let gate = LoadGate()
    /// по какому поиску сейчас список компаний в памяти ("" — полный)
    @ObservationIgnored private var leadsQuery = ""
    /// данные кабинета уже есть (копия с телефона или ответ сервера); без них на первом входе — скелетоны
    var hasData = false
    private var pendingDelete: [Int: Task<Void, Never>] = [:]
    private var pendingSegDelete: Task<Void, Never>?
    /// режим выбора подборок на обзоре
    var segSelecting = false
    var segSelected: Set<Int> = []
    var segConfirmDelete = false
    /// режим выбора лидов и групповые действия (LeadsSelect.swift)
    var leadSelecting = false
    var leadSelected: Set<Int> = []
    var leadConfirmDelete = false
    var leadMailSheet = false
    /// лист «в Sguardo» (рассылка WhatsApp в кабинете Sguardo с той же почтой)
    var leadSguardoSheet = false
    /// кому можно передать фирмы (GET /api/table/managers; у менеджера пусто — пункт скрыт)
    var bulkManagers: [Manager] = []
    /// доступ к рассылкам: не знаем / скрыт (менеджер) / закрыт (нет почты в тарифе) / есть
    var mailState: MailState = .unknown
    @ObservationIgnored var bulkOptionsLoaded = false
    @ObservationIgnored var pendingBulk: [UUID: Task<Void, Never>] = [:]

    var seenSignals: Set<Int> = Set((UserDefaults.standard.array(forKey: "seenSignals") as? [Int]) ?? [])
    var faceOn: Bool = UserDefaults.standard.object(forKey: "face") as? Bool ?? false

    // Согласие на перевод писем сторонним ИИ (App Review 5.1.2(i)). Без него текст писем на перевод не отправляется.
    var aiConsentSaved: Bool = UserDefaults.standard.bool(forKey: "aiConsent") {
        didSet { UserDefaults.standard.set(aiConsentSaved, forKey: "aiConsent") }
    }
    /// в режиме снимков CI (-fixture) согласие считается данным
    var aiConsent: Bool { fixture || aiConsentSaved }

    /// дать или отозвать согласие (алерт показывает экран; выключение в настройках — сразу)
    func setAIConsent(_ on: Bool) {
        aiConsentSaved = on
    }

    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    var unseenCount: Int { signals.filter { !seenSignals.contains($0.id) }.count }
    /// первый вход без копии на телефоне: данных ещё нет и ошибки нет — показываем скелетоны вместо пустоты
    var firstLoading: Bool { !hasData && lastError == nil && !fixture }
    func lead(_ id: Int) -> Lead? { leads.first { $0.id == id } }
    var isOwnerAccount: Bool { overview.plan == "owner" }

    // MARK: - запуск и вход

    func bootstrap() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-fixture") {
            fixture = true
            Fixture.apply(self)
            return
        }
        #endif
        if faceOn { locked = true }
        // копия с прошлого запуска — сразу на экран; проверка сессии и свежие данные идут следом, без мигания
        let fromCache: Bool = restoreLastSession()
        do {
            let d: Data = try await API.send("GET", "/api/auth/me/")
            let me: MeResponse = try API.decode(MeResponse.self, d)
            useAccount(me.user, raw: d)
            phase = .ready
            // с копией на экране обзор уже сам начал обновляться (.task) — тот же запрос не дублируем
            await refreshAll(force: !fromCache)
            startPolling()
        } catch let e as APIError where e.status == 401 {
            // сессия истекла: копию прошлого аккаунта больше не показываем
            if fromCache { clearData(); DiskCache.clearAll() }
            phase = .login
        } catch {
            if API.hasSession {
                phase = .ready
                if !isCancellation(error) { lastError = friendly(error) }
                // нет сети при запуске: на экране копия, опрос сам подтянет свежее, когда связь вернётся
                if fromCache { startPolling() }
            } else {
                phase = .login
            }
        }
    }

    func didLogin() async {
        if let d = try? await API.send("GET", "/api/auth/me/"), let me = try? API.decode(MeResponse.self, d) {
            useAccount(me.user, raw: d)
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { phase = .ready }
        await refreshAll()
        startPolling()
    }

    /// Показать копию кабинета прошлого запуска, если сессия на телефоне есть. true — копия на экране.
    private func restoreLastSession() -> Bool {
        guard API.hasSession, let acc = DiskCache.lastAccount,
              let d = DiskCache.read("me", who: acc), let me = try? API.decode(MeResponse.self, d) else { return false }
        DiskCache.account = acc
        user = me.user
        restoreCache()
        phase = .ready
        return true
    }

    /// Сервер подтвердил, кто вошёл: включаем кэш этого аккаунта (другой аккаунт — чужую копию стираем).
    private func useAccount(_ u: User, raw: Data) {
        let acc: String = u.email.lowercased()
        if let old = DiskCache.account, old != acc {
            clearData()
            DiskCache.clearAll()
        }
        user = u
        guard !acc.isEmpty else { return }
        DiskCache.account = acc
        DiskCache.lastAccount = acc
        DiskCache.write(raw, "me")
    }

    /// Сохранённые ответы сервера — на экран (без сети и анимаций). Почта и папки читают свою копию сами.
    func restoreCache() {
        var any = false
        if let d = DiskCache.read("overview"), let r = try? API.decode(OverviewResponse.self, d) { overview = r.overview; any = true }
        if let d = DiskCache.read("segments"), let r = try? API.decode(SegmentsResponse.self, d) { segments = r.segments; any = true }
        if let d = DiskCache.read("leads"), let r = try? API.decode(TableResponse.self, d) { leads = r.rows; leadsTotal = r.total; any = true }
        if let d = DiskCache.read("signals"), let r = try? API.decode(SignalsResponse.self, d) { signals = r.signals; any = true }
        if let d = DiskCache.read("prefs"), let p = Self.object(d) { prefs = (p["prefs"] as? [String: Any]) ?? [:] }
        if let d = DiskCache.read("voice"), let v = Self.object(d) { voice = (v["voice"] as? [String: Any]) ?? [:] }
        if let d = DiskCache.read("managers"), let r = try? API.decode(ManagersResponse.self, d) { managers = r.managers }
        if any { hasData = true }
    }

    private static func object(_ d: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    func logout() async {
        stopPolling()
        if !fixture { _ = try? await API.send("POST", "/api/auth/logout/") }
        resetAll()
        withAnimation { phase = .login }
    }

    /// Полный сброс: следующий аккаунт на телефоне не увидит ничего от прошлого.
    func resetAll() {
        API.clearCookies()
        URLCache.shared.removeAllCachedResponses()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        let d = UserDefaults.standard
        for k in ["seenSignals", "face", "lastEmail"] { d.removeObject(forKey: k) }
        clearData()
        DiskCache.clearAll()
        seenSignals = []; faceOn = false; locked = false; lastError = nil; toastTask?.cancel(); toast = nil
        for t in pendingDelete.values { t.cancel() }; pendingDelete = [:]
        pendingSegDelete?.cancel(); pendingSegDelete = nil
        segSelecting = false; segSelected = []; segConfirmDelete = false
        for t in pendingBulk.values { t.cancel() }; pendingBulk = [:]
        leadSelecting = false; leadSelected = []; leadConfirmDelete = false; leadMailSheet = false; leadSguardoSheet = false
        bulkManagers = []; mailState = .unknown; bulkOptionsLoaded = false
        homePath = []; leadsPath = []; mailPath = []; signalsPath = []; settingsPath = []
        leadFilter = "new"; segmentFilter = nil; tab = .home
        toastTask?.cancel(); toast = nil
    }

    /// данные кабинета в памяти — к пустому (выход, смена аккаунта)
    private func clearData() {
        gate.reset()
        mail.reset()
        folders.reset()
        user = nil
        overview = Overview()
        segments = []; leads = []; leadsTotal = 0; signals = []; managers = []; prefs = [:]; voice = [:]
        hasData = false
        leadsQuery = ""
    }

    // MARK: - данные
    // Все загрузки: одна за раз по ключу (LoadGate), ответ — на экран и на диск (DiskCache).
    // force: false — при открытии экрана / возврате в приложение: свежее 60 с не трогаем. Потянуть вниз и после действий — force.
    // Ошибка при данных на экране — тихо (строка «не обновилось»), данные не стираем; тост — только если показывать нечего.

    func refreshAll(force: Bool = true) async {
        if fixture { return }
        loading = true
        defer { loading = false; hasData = true }
        async let o: Void = loadOverview(force: force)
        async let s: Void = loadSegments(force: force)
        async let l: Void = loadLeads(force: force)
        async let g: Void = loadSignals(force: force)
        _ = await (o, s, l, g)
    }

    /// GET с сохранением ответа на диск; nil — не получилось (ошибка уже обработана) или за время запроса сменился аккаунт.
    private func fetch<T: Decodable>(_ type: T.Type, _ path: String, cache key: String?, query: [URLQueryItem] = [], quiet: Bool) async -> T? {
        let acc: String? = DiskCache.account
        do {
            let d: Data = try await API.send("GET", path, query: query)
            let v: T = try API.decode(type, d)
            guard acc == DiskCache.account, phase != .login else { return nil }
            if let key { DiskCache.write(d, key) }
            return v
        } catch {
            guard acc == DiskCache.account, phase != .login else { return nil }
            handle(error, quiet: quiet || hasData)
            return nil
        }
    }

    func loadOverview(force: Bool = true) async {
        if fixture { return }
        await gate.run("overview", force: force) { [self] in
            guard let r = await fetch(OverviewResponse.self, "/api/cabinet/overview/", cache: "overview", quiet: false) else { return false }
            overview = r.overview
            lastError = nil
            return true
        }
    }

    func loadSegments(force: Bool = true) async {
        if fixture { return }
        await gate.run("segments", force: force) { [self] in
            guard let r = await fetch(SegmentsResponse.self, "/api/cabinet/segments/", cache: "segments", quiet: true) else { return false }
            if segments != r.segments { segments = r.segments }
            return true
        }
    }

    func loadLeads(query: String = "", force: Bool = true) async {
        if fixture { return }
        // поиск — без кэша и без «свежести»: каждый запрос свой
        if !query.isEmpty {
            let q: [URLQueryItem] = [URLQueryItem(name: "limit", value: "1000"), URLQueryItem(name: "q", value: query)]
            if let r = await fetch(TableResponse.self, "/api/table/", cache: nil, query: q, quiet: false) { applyLeads(r); leadsQuery = query }
            return
        }
        // в памяти результаты поиска (экран пересоздан с пустым поиском) — полный список грузим без оглядки на «свежесть»
        let wasSearch: Bool = !leadsQuery.isEmpty
        await gate.run("leads", force: force || wasSearch) { [self] in
            let q: [URLQueryItem] = [URLQueryItem(name: "limit", value: "1000")]
            guard let r = await fetch(TableResponse.self, "/api/table/", cache: "leads", query: q, quiet: false) else { return false }
            applyLeads(r)
            leadsQuery = ""
            return true
        }
    }

    /// новый список компаний — только если он правда изменился (иначе список не перерисовывается и не прыгает)
    private func applyLeads(_ r: TableResponse) {
        if leads != r.rows {
            if leads.isEmpty {
                leads = r.rows
            } else {
                withAnimation(.easeInOut(duration: 0.25)) { leads = r.rows }
            }
        }
        if leadsTotal != r.total { leadsTotal = r.total }
    }

    func loadSignals(force: Bool = true) async {
        if fixture { return }
        await gate.run("signals", force: force) { [self] in
            guard let r = await fetch(SignalsResponse.self, "/api/cabinet/signals/", cache: "signals", quiet: true) else { return false }
            if signals != r.signals { signals = r.signals }
            return true
        }
    }

    func loadSettings(force: Bool = true) async {
        if fixture { return }
        await gate.run("settings", force: force) { [self] in
            let acc: String? = DiskCache.account
            var ok = false
            if let d = try? await API.send("GET", "/api/cabinet/prefs/"), let p = Self.object(d), acc == DiskCache.account {
                prefs = (p["prefs"] as? [String: Any]) ?? [:]
                DiskCache.write(d, "prefs")
                ok = true
            }
            if let d = try? await API.send("GET", "/api/cabinet/voice/"), let v = Self.object(d), acc == DiskCache.account {
                voice = (v["voice"] as? [String: Any]) ?? [:]
                DiskCache.write(d, "voice")
            }
            if user?.isManager != true, let d = try? await API.send("GET", "/api/cabinet/managers/"),
               let m = try? API.decode(ManagersResponse.self, d), acc == DiskCache.account {
                managers = m.managers
                DiskCache.write(d, "managers")
            }
            return ok
        }
    }

    private func handle(_ error: Error, quiet: Bool = false) {
        if let e = error as? APIError, e.status == 401 { Task { await logout() }; return }
        if isCancellation(error) { return }
        lastError = friendly(error)
        if !quiet { show(friendly(error), ok: false) }
    }

    // MARK: - действия

    func setStatus(_ id: Int, _ st: LeadStatus, undoable: Bool = true) async {
        guard let i = leads.firstIndex(where: { $0.id == id }) else { return }
        let was = leads[i].status
        guard was != st.rawValue else { return }
        withAnimation(.spring(response: 0.3)) { leads[i].status = st.rawValue }
        // «отменить» в тосте — вернуть прежний статус
        let back: () -> Void = { [weak self] in
            guard let prev = LeadStatus(rawValue: was) else { return }
            Task { await self?.setStatus(id, prev, undoable: false) }
        }
        if fixture { show(statusToast(st), undo: undoable ? back : nil, undoSeconds: Guide.undoSeconds); return }
        do {
            try await API.send("POST", "/api/table/\(id)/status/", json: ["status": st.rawValue])
            show(undoable ? statusToast(st) : String(localized: "отменено"), undo: undoable ? back : nil, undoSeconds: Guide.undoSeconds)
            Task { await loadOverview() }
        } catch {
            if let j = leads.firstIndex(where: { $0.id == id }) { leads[j].status = was }
            show(friendly(error), ok: false)
        }
    }

    /// удалить компанию из кабинета: сразу пропадает из списка, на сервер уходит через ~9 с — пока висит «отменить», можно вернуть
    func deleteLead(_ id: Int) {
        guard let i = leads.firstIndex(where: { $0.id == id }) else { return }
        let lead = leads[i]
        let who = user?.email
        withAnimation(.spring(response: 0.3)) { _ = leads.remove(at: i) }
        leadsTotal = max(0, leadsTotal - 1)
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Guide.undoDelayNs)
            // вышли из аккаунта / сменили его — ничего не удаляем и не возвращаем
            guard !Task.isCancelled, let self, self.user?.email == who else { return }
            self.pendingDelete[id] = nil
            if self.fixture { return }
            do { try await API.send("POST", "/api/table/bulk-delete/", json: ["ids": [id]]) } catch {
                self.leads.insert(lead, at: min(i, self.leads.count)); self.leadsTotal += 1
                self.show(friendly(error), ok: false)
            }
        }
        pendingDelete[id] = task
        show(String(localized: "«\(lead.name)» удалён"), undo: { [weak self] in
            guard let self else { return }
            self.pendingDelete[id]?.cancel(); self.pendingDelete[id] = nil
            withAnimation(.spring(response: 0.3)) { self.leads.insert(lead, at: min(i, self.leads.count)) }
            self.leadsTotal += 1
        }, undoSeconds: Guide.undoSeconds)
    }

    private func statusToast(_ st: LeadStatus) -> String {
        st == .new ? String(localized: "вернули в «новые»") : String(localized: "перенесено в «\(st.title)» — из «новых» убран")
    }

    func saveNote(_ id: Int, _ note: String) async {
        guard let i = leads.firstIndex(where: { $0.id == id }), (leads[i].note ?? "") != note else { return }
        leads[i].note = note
        if fixture { return }
        do { try await API.send("POST", "/api/table/\(id)/note/", json: ["note": note]) } catch { show(friendly(error), ok: false) }
    }

    func saveMessage(_ id: Int, _ text: String) async -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let i = leads.firstIndex(where: { $0.id == id }), (leads[i].message ?? "") != t else { return false }
        leads[i].message = t
        if fixture { return true }
        do {
            try await API.send("POST", "/api/table/\(id)/message/", json: ["message": t])
            return true
        } catch {
            show(friendly(error), ok: false)
            return false
        }
    }

    func setManager(_ leadId: Int, _ m: Manager?) async {
        let who: String = m?.name ?? String(localized: "вы")
        if fixture { show(String(localized: "ведёт: \(who)")); return }
        do {
            try await API.send("POST", "/api/cabinet/leads/\(leadId)/manager/", json: ["managerId": m.map { $0.id as Any } ?? NSNull()])
            if let i = leads.firstIndex(where: { $0.id == leadId }) { leads[i].managerId = m?.id; leads[i].manager = m?.name }
            show(String(localized: "ведёт: \(who)"))
        } catch { show(friendly(error), ok: false) }
    }

    func toggleSegment(_ s: Segment) async {
        guard let i = segments.firstIndex(where: { $0.id == s.id }) else { return }
        let on = !segments[i].on
        withAnimation(.spring(response: 0.3)) { segments[i].on = on }
        if fixture { show(on ? String(localized: "подборка возобновлена") : String(localized: "на паузе, лимит не тратится")); return }
        do {
            try await API.send("POST", "/api/cabinet/segments/\(s.id)/status/", json: ["status": on ? "active" : "paused"])
            show(on ? String(localized: "подборка возобновлена") : String(localized: "на паузе, лимит не тратится"))
        } catch {
            if let j = segments.firstIndex(where: { $0.id == s.id }) { segments[j].on = !on }
            show(friendly(error), ok: false)
        }
    }

    // MARK: - выбор подборок и групповые действия

    func startSegSelecting(_ first: Int? = nil) {
        withAnimation(.spring(response: 0.3)) {
            segSelecting = true
            if let first { segSelected = [first] } else { segSelected = [] }
        }
    }

    func stopSegSelecting() {
        withAnimation(.spring(response: 0.3)) {
            segSelecting = false
            segSelected = []
            segConfirmDelete = false
        }
    }

    func toggleSegSelected(_ id: Int) {
        if segSelected.contains(id) { segSelected.remove(id) } else { segSelected.insert(id) }
    }

    /// Поставить на паузу / возобновить несколько подборок с «отменить».
    func setSegments(_ ids: Set<Int>, on: Bool) async {
        let todo: [Segment] = segments.filter { ids.contains($0.id) && $0.on != on }
        guard !todo.isEmpty else {
            show(on ? String(localized: "они уже включены") : String(localized: "они уже на паузе"))
            return
        }
        withAnimation(.spring(response: 0.3)) {
            for i in segments.indices where todo.contains(where: { $0.id == segments[i].id }) { segments[i].on = on }
        }
        var done: [Int] = []
        var failure: String?
        if !fixture {
            for sg in todo {
                do {
                    try await API.send("POST", "/api/cabinet/segments/\(sg.id)/status/", json: ["status": on ? "active" : "paused"])
                    done.append(sg.id)
                } catch {
                    failure = friendly(error)
                    if let j = segments.firstIndex(where: { $0.id == sg.id }) { segments[j].on = !on }
                }
            }
        } else {
            done = todo.map(\.id)
        }
        if done.isEmpty {
            show(failure ?? String(localized: "не получилось"), ok: false)
            return
        }
        let n: Int = done.count
        var text: String = on ? String(localized: "возобновлено: \(n) подборок") : String(localized: "на паузе: \(n) подборок, лимит не тратится")
        if let failure { text = String(localized: "\(text) · остальные: \(failure)") }
        let back: Set<Int> = Set(done)
        show(text, ok: failure == nil, undo: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                await self.setSegmentsQuiet(back, on: !on)
            }
        }, undoSeconds: Guide.undoSeconds)
        Task { await loadOverview() }
    }

    /// Обратное действие без нового «отменить».
    private func setSegmentsQuiet(_ ids: Set<Int>, on: Bool) async {
        withAnimation(.spring(response: 0.3)) {
            for i in segments.indices where ids.contains(segments[i].id) { segments[i].on = on }
        }
        guard !fixture else { show(String(localized: "отменено")); return }
        var ok = true
        for id in ids {
            do { try await API.send("POST", "/api/cabinet/segments/\(id)/status/", json: ["status": on ? "active" : "paused"]) } catch {
                ok = false
                show(friendly(error), ok: false)
            }
        }
        if ok { show(String(localized: "отменено")) }
        await loadSegments()
    }

    /// Удалить подборки: сразу пропадают из списка, на сервер уходит через 5 с — пока висит «отменить», можно вернуть.
    func deleteSegments(_ ids: Set<Int>) {
        var removed: [(Int, Segment)] = []
        for i in segments.indices where ids.contains(segments[i].id) { removed.append((i, segments[i])) }
        guard !removed.isEmpty else { return }
        let who = user?.email
        withAnimation(.spring(response: 0.3)) { segments.removeAll { ids.contains($0.id) } }
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Guide.undoDelayNs)
            guard !Task.isCancelled, let self, self.user?.email == who else { return }
            self.pendingSegDelete = nil
            if self.fixture { return }
            var failed = 0
            for (_, sg) in removed {
                do { try await API.send("POST", "/api/cabinet/segments/\(sg.id)/remove/", json: [:]) } catch { failed += 1 }
            }
            if failed > 0 { self.show(String(localized: "не удалилось подборок: \(failed)"), ok: false) }
            await self.loadSegments()
            await self.loadOverview()
        }
        pendingSegDelete?.cancel()
        pendingSegDelete = task
        let title: String = removed.count == 1 ? String(localized: "подборка «\(removed[0].1.niche)» удалена") : String(localized: "удалено: \(removed.count) подборок")
        show(title, undo: { [weak self] in
            guard let self else { return }
            self.pendingSegDelete?.cancel()
            self.pendingSegDelete = nil
            withAnimation(.spring(response: 0.3)) {
                for (i, sg) in removed { self.segments.insert(sg, at: min(i, self.segments.count)) }
            }
        }, undoSeconds: Guide.undoSeconds)
    }

    func markSeen(_ id: Int) {
        seenSignals.insert(id)
        UserDefaults.standard.set(Array(seenSignals.suffix(500)), forKey: "seenSignals")
    }

    func markAllSeen() {
        let before = seenSignals
        for s in signals { seenSignals.insert(s.id) }
        UserDefaults.standard.set(Array(seenSignals.suffix(500)), forKey: "seenSignals")
        show(String(localized: "все сигналы прочитаны"), undo: { [weak self] in
            guard let self else { return }
            self.seenSignals = before
            UserDefaults.standard.set(Array(before.suffix(500)), forKey: "seenSignals")
        }, undoSeconds: Guide.undoSeconds)
    }

    /// Взять фирму из сигнала в лиды (бэкенд делает выдачу с сообщением про событие).
    func takeSignal(_ s: Signal) async -> Int? {
        if fixture { show(String(localized: "добавлено в компании")); return leads.first?.id }
        do {
            let r = try await API.post(TakeResponse.self, "/api/cabinet/signals/\(s.id)/take/")
            await loadLeads()
            show(r.already == true ? String(localized: "компания уже в списке") : String(localized: "добавлено в компании"))
            if let org = s.orgId, lead(org) != nil { return org }
            return nil
        } catch {
            show(friendly(error), ok: false)
            return nil
        }
    }

    func savePrefs(_ patch: [String: Any]) async {
        for (k, v) in patch { prefs[k] = v }
        if fixture { return }
        do {
            let d = try await API.send("POST", "/api/cabinet/prefs/", json: patch)
            if let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let p = obj["prefs"] as? [String: Any] { prefs = p }
        } catch { show(friendly(error), ok: false) }
    }

    /// Тексты: бэкенд перезаписывает все поля, поэтому отправляем полный объект с правкой.
    func saveVoice(_ patch: [String: Any]) async {
        var full = voice
        for (k, v) in patch { full[k] = v }
        voice = full
        if fixture { show(String(localized: "сохранено")); return }
        var body: [String: Any] = [:]
        for k in ["company", "name", "gender", "product", "audience", "difference", "site", "banned", "maxLength", "price", "msgLang", "productI18n"] {
            if let v = full[k] { body[k] = v }
        }
        do {
            let d = try await API.send("POST", "/api/cabinet/voice/", json: body)
            if let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let w = obj["warning"] as? String {
                show(w, ok: false)
            } else {
                show(String(localized: "сохранено"))
            }
        } catch { show(friendly(error), ok: false) }
    }

    func addManager(name: String, email: String) async -> Bool {
        if fixture { show(String(localized: "менеджер добавлен")); return true }
        do {
            let d = try await API.send("POST", "/api/cabinet/managers/", json: ["name": name, "email": email])
            let obj = (try? JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
            show((obj["invited"] as? Bool) == true ? String(localized: "менеджер добавлен, приглашение ушло на почту") : String(localized: "менеджер добавлен"))
            if let m = try? await API.get(ManagersResponse.self, "/api/cabinet/managers/") { managers = m.managers }
            return true
        } catch {
            show(friendly(error), ok: false)
            return false
        }
    }

    func removeManager(_ m: Manager) async {
        if fixture { managers.removeAll { $0.id == m.id }; return }
        do {
            try await API.send("POST", "/api/cabinet/managers/\(m.id)/remove/")
            managers.removeAll { $0.id == m.id }
            show(String(localized: "менеджер убран"))
        } catch { show(friendly(error), ok: false) }
    }

    func createSegments(niche: String, cities: [String], limit: Int, contacts: [String]) async -> [Int]? {
        if fixture { return [1] }
        do {
            var body: [String: Any] = ["niche": niche, "cities": cities, "limit": limit]
            if !contacts.isEmpty { body["contacts"] = contacts }
            let r = try await API.post(CreateSegmentsResponse.self, "/api/cabinet/segments/", json: body)
            if let dup = r.dup, !dup.isEmpty { show(String(localized: "уже были: \(dup.joined(separator: ", "))"), ok: false) }
            await loadSegments()
            return r.ids ?? []
        } catch {
            show(friendly(error), ok: false)
            return nil
        }
    }

    func collectStatus() async -> [CollectSeg] {
        if fixture { return [] }
        return (try? await API.get(CollectStatus.self, "/api/table/collect-status/").segments) ?? []
    }

    // MARK: - фон

    func startPolling() {
        guard !fixture else { return }
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 90_000_000_000)
                await self?.loadSignals(force: false)
                await self?.loadOverview(force: false)
            }
        }
    }

    func stopPolling() { pollTask?.cancel(); pollTask = nil }

    // MARK: - Face ID

    /// заблокировать экран: тост с «отменить» убираем, чтобы им нельзя было ничего сделать из-под замка
    func lock() {
        locked = true
        toastTask?.cancel()
        toast = nil
    }

    func setFace(_ on: Bool) {
        faceOn = on
        UserDefaults.standard.set(on, forKey: "face")
    }

    func requestFace(_ on: Bool) {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            show(String(localized: "на этом телефоне нет Face ID или код-пароля"), ok: false)
            return
        }
        authenticating = true
        wentBackground = false
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: on ? String(localized: "Включить вход по Face ID") : String(localized: "Выключить вход по Face ID")) { ok, _ in
            Task { @MainActor in
                if ok {
                    self.setFace(on)
                    // снимаем замок, только если он поставлен не уходом в фон
                    if !self.wentBackground { self.locked = false }
                    self.show(on ? String(localized: "вход по Face ID включён") : String(localized: "вход по Face ID выключен"))
                } else { self.show(String(localized: "не подтверждено — настройка не изменилась"), ok: false) }
                // сцена возвращается в .active чуть позже колбэка — снимаем флаг с запасом
                try? await Task.sleep(nanoseconds: 800_000_000)
                self.authenticating = false
            }
        }
    }

    // MARK: - навигация и тосты

    /// или обратимо запросом). По умолчанию 5 с — для прочих тостов с «отменить».
    /// или обратимо запросом). По умолчанию 5 с — для мест, где сервер получает действие через 5 с (bulkDelete в LeadsSelect).
    func show(_ text: String, ok: Bool = true, undo: (() -> Void)? = nil, long: Bool = false, undoSeconds: Double = 5) {
        if text.isEmpty { return } // отменённый запрос — не тост «сеть недоступна»
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { toast = Toast(text: text, ok: ok, undo: undo) }
        if !ok { UINotificationFeedbackGenerator().notificationOccurred(.error) }
        toastTask?.cancel()
        let hold: UInt64 = (undo == nil && !long) ? 3_200_000_000 : (undo == nil ? 5_000_000_000 : UInt64(undoSeconds * 1_000_000_000))
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: hold)
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil }
        }
    }

    func open(_ r: Route) {
        switch tab {
        case .home: homePath.append(r)
        case .leads: leadsPath.append(r)
        case .mail: mailPath.append(r)
        case .signals: signalsPath.append(r)
        case .settings: settingsPath.append(r)
        }
    }

    func pop() {
        switch tab {
        case .home: if !homePath.isEmpty { homePath.removeLast() }
        case .leads: if !leadsPath.isEmpty { leadsPath.removeLast() }
        case .mail: if !mailPath.isEmpty { mailPath.removeLast() }
        case .signals: if !signalsPath.isEmpty { signalsPath.removeLast() }
        case .settings: if !settingsPath.isEmpty { settingsPath.removeLast() }
        }
    }

    var currentPathEmpty: Bool {
        switch tab {
        case .home: return homePath.isEmpty
        case .leads: return leadsPath.isEmpty
        case .mail: return mailPath.isEmpty
        case .signals: return signalsPath.isEmpty
        case .settings: return settingsPath.isEmpty
        }
    }

    func clearPath(_ t: Tab) {
        switch t {
        case .home: homePath = []
        case .leads: leadsPath = []
        case .mail: mailPath = []
        case .signals: signalsPath = []
        case .settings: settingsPath = []
        }
    }
}

/// «1 подборка», «3 подборки», «5 подборок». Только русский — для интерфейса НЕ использовать:
/// множественное число на 8 языках — через String(localized: "\(n) подборок") и plural в Localizable.xcstrings (I18N.md).
func ruCount(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let m10 = n % 10, m100 = n % 100
    let w: String
    if m10 == 1 && m100 != 11 { w = one }
    else if (2...4).contains(m10) && !(12...14).contains(m100) { w = few }
    else { w = many }
    return "\(n) \(w)"
}
