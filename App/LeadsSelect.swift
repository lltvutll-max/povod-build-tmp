import SwiftUI
import UIKit

// Мультивыбор лидов и групповые действия — как полоса BulkBar в веб-кабинете (CabinetContent.tsx).
// Бэкенд: /api/table/bulk-delete, bulk-status, bulk-manager, managers, mail-lists, to-mail, to-sguardo, export (src/api/routes/table.ts).
// id лида в приложении = id организации (org id), его и ждут все эти запросы.

// MARK: - модели почты

enum MailState: Equatable { case unknown, hidden, locked, ok }

enum MailTarget: Hashable {
    case campaign(Int)
    case list(Int)
    case new
}

struct MailList: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let total: Int
    private enum K: String, CodingKey { case id, name, total }
    init(id: Int, name: String, total: Int) { self.id = id; self.name = name; self.total = total }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = c.flexInt(.id) ?? 0; name = c.str(.name) ?? String(localized: "база"); total = c.flexInt(.total) ?? 0
    }
}

struct MailCampaign: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let listId: Int?
    let listName: String
    let status: String
    private enum K: String, CodingKey { case id, name, listId, listName, status }
    init(id: Int, name: String, listId: Int?, listName: String, status: String) {
        self.id = id; self.name = name; self.listId = listId; self.listName = listName; self.status = status
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = c.flexInt(.id) ?? 0; name = c.str(.name) ?? String(localized: "рассылка"); listId = c.flexInt(.listId)
        listName = c.str(.listName) ?? ""; status = c.str(.status) ?? ""
    }
}

struct MailLists: Decodable {
    let access: String
    let lists: [MailList]
    let campaigns: [MailCampaign]
    private enum K: String, CodingKey { case access, lists, campaigns }
    init(access: String, lists: [MailList], campaigns: [MailCampaign]) { self.access = access; self.lists = lists; self.campaigns = campaigns }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        access = c.str(.access) ?? "client"
        lists = (try? c.decodeIfPresent([MailList].self, forKey: .lists)) ?? []
        campaigns = (try? c.decodeIfPresent([MailCampaign].self, forKey: .campaigns)) ?? []
    }
}

struct MailCampaignState: Decodable, Hashable {
    let name: String
    let running: Bool
}

struct MailResult: Decodable, Hashable {
    let added: Int
    let noEmail: Int
    let duplicates: Int
    let blacklisted: Int
    let campaign: MailCampaignState?
    private enum K: String, CodingKey { case added, noEmail, duplicates, blacklisted, campaign }
    init(added: Int, noEmail: Int, duplicates: Int, blacklisted: Int, campaign: MailCampaignState?) {
        self.added = added; self.noEmail = noEmail; self.duplicates = duplicates; self.blacklisted = blacklisted; self.campaign = campaign
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        added = c.flexInt(.added) ?? 0; noEmail = c.flexInt(.noEmail) ?? 0
        duplicates = c.flexInt(.duplicates) ?? 0; blacklisted = c.flexInt(.blacklisted) ?? 0
        campaign = try? c.decodeIfPresent(MailCampaignState.self, forKey: .campaign)
    }
}

/// Ответ /api/table/to-sguardo: при dryRun — toAdd/withPhone/noPhone, иначе added/updated/noPhone.
struct SguardoResult: Decodable, Hashable {
    let toAdd: Int
    let added: Int
    let updated: Int
    let noPhone: Int
    let noMessage: Int
    let whatsapp: Bool
    private enum K: String, CodingKey { case toAdd, added, updated, noPhone, noMessage, whatsapp }
    init(toAdd: Int, added: Int, updated: Int, noPhone: Int, noMessage: Int, whatsapp: Bool) {
        self.toAdd = toAdd; self.added = added; self.updated = updated; self.noPhone = noPhone; self.noMessage = noMessage; self.whatsapp = whatsapp
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        toAdd = c.flexInt(.toAdd) ?? 0; added = c.flexInt(.added) ?? 0; updated = c.flexInt(.updated) ?? 0
        noPhone = c.flexInt(.noPhone) ?? 0; noMessage = c.flexInt(.noMessage) ?? 0
        whatsapp = (try? c.decodeIfPresent(Bool.self, forKey: .whatsapp)) ?? false
    }
}

/// Флаги функций версии. Вернуть «в Sguardo» — поставить toSguardo = true.
enum Features {
    /// массовое «в Sguardo» (рассылка WhatsApp в кабинете Sguardo); в iOS 1.0 скрыто
    static let toSguardo: Bool = false
}

/// Адрес Sguardo: кабинет заводится там тем же email, что и в Поводе.
let sguardoURL: URL = URL(string: "https://disify.dev/sguardo/")!

/// Владелец записи «кто ведёт» до групповой передачи — для «отменить».
struct ManagerRef: Hashable {
    let id: Int?
    let name: String?
}

struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// «1 компания», «3 компании», «5 компаний» — на языке интерфейса (plural в Localizable.xcstrings).
func companies(_ n: Int) -> String { String(localized: "\(n) компаний") }

// MARK: - состояние и запросы

extension Store {
    /// выбранные, которые ещё есть в списке (в порядке списка)
    func selectedLeadIds() -> [Int] {
        leads.filter { leadSelected.contains($0.id) }.map(\.id)
    }

    func startLeadSelecting(_ first: Int? = nil) {
        withAnimation(.spring(response: 0.3)) {
            leadSelecting = true
            if let first { leadSelected = [first] } else { leadSelected = [] }
        }
        Task { await loadBulkOptions() }
    }

    func stopLeadSelecting() {
        withAnimation(.spring(response: 0.3)) {
            leadSelecting = false
            leadSelected = []
            leadConfirmDelete = false
        }
    }

    func toggleLeadSelected(_ id: Int) {
        if leadSelected.contains(id) { leadSelected.remove(id) } else { leadSelected.insert(id) }
    }

    /// Менеджеры и доступ к почте — один раз за вход (повтор, если сеть подвела).
    func loadBulkOptions() async {
        if bulkOptionsLoaded { return }
        bulkOptionsLoaded = true
        if fixture { mailState = .ok; return }
        if user?.isManager == true {
            bulkManagers = []
            mailState = .hidden
            return
        }
        if let r = try? await API.get(ManagersResponse.self, "/api/table/managers/") { bulkManagers = r.managers }
        do {
            _ = try await API.get(MailLists.self, "/api/table/mail-lists/")
            mailState = .ok
        } catch let e as APIError where e.status == 403 {
            mailState = .locked
        } catch {
            mailState = .unknown
            bulkOptionsLoaded = false
        }
    }

    // статус

    func bulkStatus(_ ids: [Int], _ st: LeadStatus) async {
        var prev: [Int: String] = [:]
        for l in leads where ids.contains(l.id) && l.status != st.rawValue { prev[l.id] = l.status }
        guard !prev.isEmpty else {
            show(String(localized: "у них уже статус «\(st.title)»"))
            return
        }
        let target: [Int: String] = prev.mapValues { (_: String) -> String in st.rawValue }
        applyStatuses(target)
        let changed: [Int] = Array(prev.keys)
        let text: String = String(localized: "статус «\(st.title)»: \(companies(changed.count))")
        let undo: () -> Void = { [weak self] in
            Task { @MainActor in await self?.restoreStatuses(prev) }
        }
        if fixture { show(text, undo: undo, undoSeconds: Guide.undoSeconds); return }
        do {
            try await API.send("POST", "/api/table/bulk-status/", json: ["ids": changed, "status": st.rawValue])
            show(text, undo: undo, undoSeconds: Guide.undoSeconds)
            Task { await loadOverview() }
        } catch {
            applyStatuses(prev)
            show(friendly(error), ok: false)
        }
    }

    private func applyStatuses(_ map: [Int: String]) {
        withAnimation(.spring(response: 0.3)) {
            for i in leads.indices {
                if let s = map[leads[i].id] { leads[i].status = s }
            }
        }
    }

    /// «отменить»: прежние статусы — по одному запросу на каждую группу прежнего статуса.
    private func restoreStatuses(_ prev: [Int: String]) async {
        applyStatuses(prev)
        if fixture { show(String(localized: "отменено")); return }
        let groups: [String: [Int]] = Dictionary(grouping: Array(prev.keys)) { (id: Int) -> String in prev[id] ?? "new" }
        var failure: String?
        for (status, gids) in groups {
            do { try await API.send("POST", "/api/table/bulk-status/", json: ["ids": gids, "status": status]) } catch { failure = friendly(error) }
        }
        if let failure {
            show(failure, ok: false)
            await loadLeads()
        } else {
            show(String(localized: "отменено"))
        }
        Task { await loadOverview() }
    }

    // менеджер

    func bulkManager(_ ids: [Int], _ m: Manager?) async {
        var prev: [Int: ManagerRef] = [:]
        for l in leads where ids.contains(l.id) && l.managerId != m?.id { prev[l.id] = ManagerRef(id: l.managerId, name: l.manager) }
        guard !prev.isEmpty else {
            let who: String = m?.name ?? ""
            show(m == nil ? String(localized: "их и так ведёте вы") : String(localized: "их уже ведёт \(who)"))
            return
        }
        let ref = ManagerRef(id: m?.id, name: m?.name)
        let target: [Int: ManagerRef] = prev.mapValues { (_: ManagerRef) -> ManagerRef in ref }
        applyManagers(target)
        let changed: [Int] = Array(prev.keys)
        let count: String = companies(changed.count)
        let text: String = m.map { (x: Manager) -> String in String(localized: "ведёт \(x.name): \(count)") } ?? String(localized: "вернули себе: \(count)")
        let undo: () -> Void = { [weak self] in
            Task { @MainActor in await self?.restoreManagers(prev) }
        }
        if fixture { show(text, undo: undo, undoSeconds: Guide.undoSeconds); return }
        do {
            try await API.send("POST", "/api/table/bulk-manager/", json: managerBody(changed, m?.id))
            show(text, undo: undo, undoSeconds: Guide.undoSeconds)
        } catch {
            applyManagers(prev)
            show(friendly(error), ok: false)
        }
    }

    private func managerBody(_ ids: [Int], _ managerId: Int?) -> [String: Any] {
        var body: [String: Any] = ["ids": ids]
        if let managerId { body["managerId"] = managerId } else { body["managerId"] = NSNull() }
        return body
    }

    private func applyManagers(_ map: [Int: ManagerRef]) {
        for i in leads.indices {
            if let r = map[leads[i].id] {
                leads[i].managerId = r.id
                leads[i].manager = r.name
            }
        }
    }

    private func restoreManagers(_ prev: [Int: ManagerRef]) async {
        applyManagers(prev)
        if fixture { show(String(localized: "отменено")); return }
        let groups: [Int: [Int]] = Dictionary(grouping: Array(prev.keys)) { (id: Int) -> Int in prev[id]?.id ?? 0 }
        var failure: String?
        for (mid, gids) in groups {
            do { try await API.send("POST", "/api/table/bulk-manager/", json: managerBody(gids, mid == 0 ? nil : mid)) } catch { failure = friendly(error) }
        }
        if let failure {
            show(failure, ok: false)
            await loadLeads()
        } else {
            show(String(localized: "отменено"))
        }
    }

    // удаление

    /// Убрать выбранные: сразу пропадают, запрос bulk-delete уходит через 9 с — пока висит «отменить», можно вернуть.
    func bulkDelete(_ ids: Set<Int>) {
        var removed: [(Int, Lead)] = []
        for i in leads.indices where ids.contains(leads[i].id) { removed.append((i, leads[i])) }
        guard !removed.isEmpty else { return }
        let gone: [Int] = removed.map { (pair: (Int, Lead)) -> Int in pair.1.id }
        let who = user?.email
        withAnimation(.spring(response: 0.3)) { leads.removeAll { ids.contains($0.id) } }
        leadsTotal = max(0, leadsTotal - removed.count)
        let key = UUID()
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Guide.undoDelayNs)
            // вышли из аккаунта / сменили его — ничего не удаляем и не возвращаем
            guard !Task.isCancelled, let self, self.user?.email == who else { return }
            self.pendingBulk[key] = nil
            if self.fixture { return }
            do {
                try await API.send("POST", "/api/table/bulk-delete/", json: ["ids": gone])
                Task { await self.loadOverview() }
            } catch {
                self.putBack(removed)
                self.show(friendly(error), ok: false)
            }
        }
        pendingBulk[key] = task
        show(String(localized: "убрано: \(companies(removed.count))"), undo: { [weak self] in
            guard let self else { return }
            self.pendingBulk[key]?.cancel()
            self.pendingBulk[key] = nil
            self.putBack(removed)
        }, undoSeconds: Guide.undoSeconds)
    }

    private func putBack(_ removed: [(Int, Lead)]) {
        var back = 0
        withAnimation(.spring(response: 0.3)) {
            for (i, l) in removed {
                let has: Bool = leads.contains { (x: Lead) -> Bool in x.id == l.id }
                if has { continue }
                leads.insert(l, at: min(i, leads.count))
                back += 1
            }
        }
        leadsTotal += back
    }

    // скачать

    /// Файл выбранных (xlsx или csv) во временную папку — дальше «поделиться».
    func exportLeads(_ ids: [Int], format: String) async -> URL? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("povod-companies-\(f.string(from: .now)).\(format)")
        do {
            let data: Data
            if fixture {
                data = Data("название;город\n".utf8)
            } else {
                data = try await API.send("POST", "/api/table/export/", json: ["ids": ids, "format": format])
            }
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            show(friendly(error), ok: false)
            return nil
        }
    }

    // рассылка

    func fetchMailLists() async throws -> MailLists {
        if fixture {
            let en: Bool = FixtureText.english
            let list1: String = en ? "London coffee shops" : "Кофейни Казань"
            let list2: String = en ? "Manchester dental clinics" : "Стоматологии Санкт-Петербург"
            let camp1: String = en ? "Coffee shops · autumn" : "Кофейни · осень"
            return MailLists(access: "owner", lists: [
                MailList(id: 1, name: list1, total: 120),
                MailList(id: 2, name: list2, total: 48),
            ], campaigns: [
                MailCampaign(id: 1, name: camp1, listId: 1, listName: list1, status: "paused"),
            ])
        }
        do {
            let r = try await API.get(MailLists.self, "/api/table/mail-lists/")
            mailState = .ok
            return r
        } catch let e as APIError where e.status == 403 {
            mailState = .locked
            throw e
        }
    }

    func toMail(_ ids: [Int], _ target: MailTarget, name: String, dryRun: Bool) async throws -> MailResult {
        if fixture {
            let chosen: [Lead] = leads.filter { ids.contains($0.id) }
            let withMail: Int = chosen.filter { ($0.email ?? "").contains("@") }.count
            var camp: MailCampaignState?
            if case .campaign = target { camp = MailCampaignState(name: FixtureText.pick("Кофейни · осень", "Coffee shops · autumn"), running: false) }
            return MailResult(added: withMail, noEmail: chosen.count - withMail, duplicates: 0, blacklisted: 0, campaign: camp)
        }
        var body: [String: Any] = ["ids": ids, "dryRun": dryRun]
        switch target {
        case .campaign(let id): body["campaignId"] = id
        case .list(let id): body["listId"] = id
        case .new: body["newList"] = name.isEmpty ? String(localized: "новая база") : name
        }
        return try await API.post(MailResult.self, "/api/table/to-mail/", json: body)
    }

    // Sguardo

    /// Выбранные — в рассылку WhatsApp Sguardo (тот же email). Нет кабинета Sguardo — APIError 409.
    func toSguardo(_ ids: [Int], dryRun: Bool) async throws -> SguardoResult {
        if fixture {
            if fixtureMail == "leads-sguardo-none" {
                throw APIError(status: 409, message: "Нет кабинета Sguardo с этой почтой: создайте кабинет в Sguardo тем же email, что и в Поводе")
            }
            let chosen: [Lead] = leads.filter { ids.contains($0.id) }
            let withPhone: Int = chosen.filter { ($0.phone ?? "").count >= 7 }.count
            return SguardoResult(toAdd: withPhone, added: withPhone, updated: 0, noPhone: chosen.count - withPhone, noMessage: 0, whatsapp: true)
        }
        return try await API.post(SguardoResult.self, "/api/table/to-sguardo/", json: ["ids": ids, "dryRun": dryRun])
    }

    func sguardoDone(_ r: SguardoResult) {
        stopLeadSelecting()
        var text: String = String(localized: "в Sguardo добавлено \(r.added)")
        if r.updated > 0 { text = String(localized: "\(text) · уже были \(r.updated)") }
        text = String(localized: "\(text) · без телефона \(r.noPhone)")
        if !r.whatsapp { text = String(localized: "\(text). подключите WhatsApp в Sguardo, чтобы сообщения ушли") }
        show(text, long: true)
    }

    func mailDone(_ r: MailResult) {
        stopLeadSelecting()
        let dups: Int = r.duplicates + r.blacklisted
        var text: String = String(localized: "в базу добавлено \(r.added) · без почты \(r.noEmail) · дубли \(dups)")
        if let c = r.campaign, !c.running { text = String(localized: "\(text). рассылка на паузе — запустите её в разделе «почта»") }
        show(text, long: true)
    }
}

// MARK: - панель действий

/// Панель действий с выбранными компаниями (вместо таб-бара).
struct LeadSelectionBar: View {
    @Environment(Store.self) private var store
    @Binding var share: ShareFile?

    var body: some View {
        let ids: [Int] = store.selectedLeadIds()
        let none: Bool = ids.isEmpty
        let showManagers: Bool = !store.bulkManagers.isEmpty && store.user?.isManager != true
        HStack(spacing: 2) {
            statusMenu(ids, none: none)
            if showManagers { managerMenu(ids, none: none) }
            if store.mailState != .hidden { mailItem(none: none) }
            if Features.toSguardo && store.user?.isManager != true { sguardoItem(none: none) }
            fileMenu(ids, none: none)
            Button {
                haptic()
                store.leadConfirmDelete = true
            } label: { itemLabel("trash", String(localized: "удалить"), dim: none) }
            .buttonStyle(PressStyle())
            .disabled(none)
        }
        .padding(.horizontal, 4).padding(.vertical, 4)
        .frame(minHeight: 64)
        .glass(.bar, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    private func itemLabel(_ icon: String, _ title: String, dim: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.title3).frame(minHeight: 25)
            Text(title).font(Typo.body(10.5, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(Pal.ink.opacity(dim ? 0.3 : 1))
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    private func statusMenu(_ ids: [Int], none: Bool) -> some View {
        Menu {
            ForEach(LeadStatus.allCases, id: \.self) { (s: LeadStatus) in
                Button(s.title) {
                    store.stopLeadSelecting()
                    Task { await store.bulkStatus(ids, s) }
                }
            }
        } label: { itemLabel("flag", String(localized: "статус"), dim: none) }
        .disabled(none)
    }

    private func managerMenu(_ ids: [Int], none: Bool) -> some View {
        Menu {
            ForEach(store.bulkManagers) { (m: Manager) in
                Button(m.name) {
                    store.stopLeadSelecting()
                    Task { await store.bulkManager(ids, m) }
                }
            }
            Divider()
            Button("забрать себе") {
                store.stopLeadSelecting()
                Task { await store.bulkManager(ids, nil) }
            }
        } label: { itemLabel("person.crop.circle.badge.checkmark", String(localized: "менеджеру"), dim: none) }
        .disabled(none)
    }

    private func mailItem(none: Bool) -> some View {
        let locked: Bool = store.mailState == .locked
        return Button {
            haptic()
            if locked {
                store.show(String(localized: "рассылки пока недоступны для вашего аккаунта"), ok: false)
            } else {
                store.leadMailSheet = true
            }
        } label: { itemLabel("envelope.badge", String(localized: "в рассылку"), dim: none || locked) }
        .buttonStyle(PressStyle())
        .disabled(none)
    }

    private func sguardoItem(none: Bool) -> some View {
        Button {
            haptic()
            store.leadSguardoSheet = true
        } label: { itemLabel("paperplane", String(localized: "в Sguardo"), dim: none) }
        .buttonStyle(PressStyle())
        .disabled(none)
    }

    private func fileMenu(_ ids: [Int], none: Bool) -> some View {
        Menu {
            Button("таблица xlsx") { download(ids, "xlsx") }
            Button("файл csv") { download(ids, "csv") }
        } label: { itemLabel("square.and.arrow.down", String(localized: "скачать"), dim: none) }
        .disabled(none)
    }

    private func download(_ ids: [Int], _ format: String) {
        Task {
            if let url = await store.exportLeads(ids, format: format) { share = ShareFile(url: url) }
        }
    }
}

/// Системное «поделиться» для скачанного файла.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - лист «в рассылку»

/// Как MailDialog в вебе: рассылка (её база), готовая база или новая; сначала считаем без записи.
struct LeadsMailSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let ids: [Int]
    @State private var data: MailLists?
    @State private var err: String?
    @State private var pick: MailTarget?
    @State private var name = ""
    @State private var preview: MailResult?
    @State private var counting = false
    @State private var busy = false

    var body: some View {
        SheetBox(title: String(localized: "в рассылку"), subtitle: String(localized: "выбрано: \(companies(ids.count)). без почты, дубли и стоп-лист пропустим")) {
            content
        }
        .task { await load() }
        .onChange(of: pick) { _, _ in Task { await count() } }
        .interactiveDismissDisabled(busy)
    }

    @ViewBuilder private var content: some View {
        if let data {
            if !data.campaigns.isEmpty {
                Cap(String(localized: "рассылки"))
                ForEach(data.campaigns) { (c: MailCampaign) in
                    option(.campaign(c.id), c.name, campaignLine(c))
                }
            }
            Cap(String(localized: "базы получателей"))
            ForEach(data.lists) { (l: MailList) in
                option(.list(l.id), l.name, String(localized: "адресов: \(Fmt.num(l.total))"))
            }
            option(.new, String(localized: "новая база"), String(localized: "назовите её — она появится в разделе почты"))
            if pick == .new {
                TextField("", text: $name, prompt: Text("название базы").foregroundColor(Pal.fg3))
                    .font(Typo.body(16)).foregroundStyle(Pal.ink)
                    .padding(.horizontal, 16).frame(minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Pal.surface.opacity(0.7)))
                    .padding(.horizontal, 8).padding(.top, 4)
                    .submitLabel(.done)
            }
            previewLine
            if let err { errorLine(err) }
            buttons
        } else if let err {
            errorLine(err)
            Button { dismiss() } label: {
                Text("закрыть").font(Typo.body(16, .semibold)).foregroundStyle(Pal.ink)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(PressStyle())
        } else {
            HStack(spacing: 10) {
                ProgressView().tint(Pal.ink)
                Text("загружаем базы…").font(Typo.body(15)).foregroundStyle(Pal.fg2)
            }
            .padding(.horizontal, 8).padding(.vertical, 24)
        }
    }

    private func option(_ key: MailTarget, _ title: String, _ sub: String) -> some View {
        let on: Bool = pick == key
        return SheetOption(icon: nil, title: title, subtitle: sub, on: on, action: {
            pick = key
            err = nil
        }, trailing: {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(on ? Pal.ink : Pal.ink.opacity(0.3))
        })
    }

    private func campaignLine(_ c: MailCampaign) -> String {
        let st: String = c.status == "running" ? String(localized: "идёт") : (c.status == "draft" ? String(localized: "черновик") : String(localized: "на паузе"))
        return c.listName.isEmpty ? st : String(localized: "база «\(c.listName)» · \(st)")
    }

    @ViewBuilder private var previewLine: some View {
        if pick != nil {
            HStack(spacing: 8) {
                Image(systemName: "envelope.open").font(.body).foregroundStyle(Pal.ink.opacity(0.7))
                if counting && preview == nil {
                    Text("считаем…").font(Typo.body(14)).foregroundStyle(Pal.fg2)
                } else if let p = preview {
                    Text("добавим \(p.added) · без почты \(p.noEmail) · уже в базе \(p.duplicates + p.blacklisted)")
                        .font(Typo.body(14, .semibold)).foregroundStyle(Pal.ink)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("посчитать не получилось — можно всё равно добавить").font(Typo.body(14)).foregroundStyle(Pal.fg2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Pal.ink.opacity(0.06)))
            .padding(.horizontal, 8).padding(.top, 12)
        }
    }

    private func errorLine(_ text: String) -> some View {
        Text(text).font(Typo.body(14)).foregroundStyle(Pal.danger)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8).padding(.top, 10)
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button { Task { await submit() } } label: {
                Text(busy ? "добавляем…" : "добавить").font(Typo.body(16, .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50).primaryFill()
            }
            .buttonStyle(PressStyle())
            .disabled(pick == nil || busy)
            .opacity(pick == nil ? 0.45 : 1)
            Button { dismiss() } label: {
                Text("отмена").font(Typo.body(16, .semibold)).foregroundStyle(Pal.ink)
                    .padding(.horizontal, 20).frame(minHeight: 50)
                    .background(Capsule().fill(Pal.surface.opacity(0.7)))
            }
            .buttonStyle(PressStyle())
            .disabled(busy)
        }
        .padding(.horizontal, 8).padding(.top, 16)
    }

    private func load() async {
        do {
            data = try await store.fetchMailLists()
            if store.fixture && store.fixtureMail == "leads-mail" { pick = .campaign(1) }
        } catch let e as APIError where e.status == 403 {
            err = e.message
        } catch {
            err = friendly(error)
        }
    }

    private func count() async {
        guard let p = pick else { preview = nil; return }
        counting = true
        preview = nil
        let r: MailResult? = try? await store.toMail(ids, p, name: name.trimmingCharacters(in: .whitespaces), dryRun: true)
        if pick == p {
            preview = r
            counting = false
        }
    }

    private func submit() async {
        guard let p = pick, !busy else { return }
        let n: String = name.trimmingCharacters(in: .whitespaces)
        if p == .new && n.isEmpty {
            err = String(localized: "назовите новую базу")
            return
        }
        busy = true
        err = nil
        do {
            let r = try await store.toMail(ids, p, name: n, dryRun: false)
            busy = false
            dismiss()
            store.mailDone(r)
        } catch {
            busy = false
            err = friendly(error)
        }
    }
}

// MARK: - лист «в Sguardo»

/// Выбранные компании — в рассылку WhatsApp кабинета Sguardo с той же почтой (как SguardoDialog в вебе).
/// Сразу считаем без записи: «добавим N · без телефона M»; нет кабинета Sguardo — кнопка «открыть Sguardo».
struct LeadsSguardoSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let ids: [Int]
    @State private var preview: SguardoResult?
    @State private var err: String?
    @State private var noWorkspace = false
    @State private var busy = false

    var body: some View {
        SheetBox(title: String(localized: "в Sguardo"), subtitle: subtitle) {
            content
        }
        .task { await count() }
        .interactiveDismissDisabled(busy)
    }

    private var subtitle: String {
        String(localized: "выбрано: \(companies(ids.count)). Sguardo проверит номера в WhatsApp и напишет первым — по одной компании, с паузами и дневным лимитом")
    }

    @ViewBuilder private var content: some View {
        previewLine
        if let p = preview, !p.whatsapp {
            note(String(localized: "в Sguardo ещё не подключён WhatsApp: компании встанут в очередь, подключите его в Sguardo → Настройки → Каналы"))
        }
        if let err { errorLine(err) }
        buttons
    }

    @ViewBuilder private var previewLine: some View {
        if err == nil {
            HStack(spacing: 8) {
                Image(systemName: "paperplane").font(.body).foregroundStyle(Pal.ink.opacity(0.7))
                if let p = preview {
                    Text(previewText(p))
                        .font(Typo.body(14, .semibold)).foregroundStyle(Pal.ink)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("считаем…").font(Typo.body(14)).foregroundStyle(Pal.fg2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Pal.ink.opacity(0.06)))
            .padding(.horizontal, 8).padding(.top, 12)
        }
    }

    private func previewText(_ p: SguardoResult) -> String {
        var t: String = String(localized: "добавим \(p.toAdd) · без телефона \(p.noPhone)")
        if p.noMessage > 0 { t = String(localized: "\(t) · без текста \(p.noMessage)") }
        return t
    }

    private func note(_ text: String) -> some View {
        Text(text).font(Typo.body(14)).foregroundStyle(Pal.fg2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8).padding(.top, 10)
    }

    private func errorLine(_ text: String) -> some View {
        Text(text).font(Typo.body(14)).foregroundStyle(Pal.danger)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8).padding(.top, 10)
    }

    private var canAdd: Bool { (preview?.toAdd ?? 0) > 0 && !busy }

    private var buttons: some View {
        HStack(spacing: 10) {
            if noWorkspace {
                Button { openURL(sguardoURL) } label: {
                    Text("открыть Sguardo").font(Typo.body(16, .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50).primaryFill()
                }
                .buttonStyle(PressStyle())
            } else {
                Button { Task { await submit() } } label: {
                    Text(busy ? "добавляем…" : "добавить").font(Typo.body(16, .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50).primaryFill()
                }
                .buttonStyle(PressStyle())
                .disabled(!canAdd)
                .opacity(canAdd || busy ? 1 : 0.45)
            }
            Button { dismiss() } label: {
                Text("отмена").font(Typo.body(16, .semibold)).foregroundStyle(Pal.ink)
                    .padding(.horizontal, 20).frame(minHeight: 50)
                    .background(Capsule().fill(Pal.surface.opacity(0.7)))
            }
            .buttonStyle(PressStyle())
            .disabled(busy)
        }
        .padding(.horizontal, 8).padding(.top, 16)
    }

    private func fail(_ error: Error) {
        if let e = error as? APIError, e.status == 409 {
            noWorkspace = true
            err = e.message
        } else {
            err = friendly(error)
        }
    }

    private func count() async {
        do {
            preview = try await store.toSguardo(ids, dryRun: true)
        } catch {
            fail(error)
        }
    }

    private func submit() async {
        guard canAdd else { return }
        busy = true
        err = nil
        do {
            let r: SguardoResult = try await store.toSguardo(ids, dryRun: false)
            busy = false
            dismiss()
            store.sguardoDone(r)
        } catch {
            busy = false
            fail(error)
        }
    }
}
