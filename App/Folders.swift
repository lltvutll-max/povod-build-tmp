import SwiftUI

// Папки лидов (11.11.2026, просьба владельца): по умолчанию папка = подборка «ниша · город».
// Свои папки: объединение нескольких подборок в одну (автосервисы ЕКБ + Пермь), переименование, ручной перенос лида
// в любую папку, удаление папки (лиды возвращаются в папки подборок).
// С версии «папки на сервере» (11.11.2026) источник правды — сервер (/api/cabinet/folders/*, общие с сайтом):
// при первом запуске локальные папки с телефона один раз уходят на сервер (POST import, идемпотентно по названию),
// дальше — GET и правки через API: сразу меняем у себя, ответ сервера (полное состояние) заменяет копию, ошибка — откат.
// Менеджер (canEdit=false) — только просмотр. Без сети — последняя копия с сервера, правки закрыты с причиной.

struct LeadFolder: Codable, Identifiable, Hashable {
    /// номер папки на сервере строкой («12» → id для показа "f:12"); пока сервер не ответил на «создать» — "tmp-<uuid>"
    var id: String
    var name: String
    /// подборки (ключ «ниша|город» в нижнем регистре), которые входят в папку целиком
    var keys: [String]
    /// лиды, перенесённые сюда вручную
    var leadIds: [Int]
}

/// Папка для показа: своя или папка подборки.
struct FolderView: Identifiable, Hashable {
    let id: String          // "f:<номер>" своя, "k:<ключ>" подборка
    let name: String
    let count: Int
    let custom: Bool
}

/// Ответ /api/cabinet/folders/*: каждое изменение отвечает полным состоянием.
struct FoldersState: Decodable {
    let canEdit: Bool
    let folders: [LeadFolder]
    /// «создать» и «объединить»: id новой папки ("f:12")
    let newId: String?
    /// «объединить»: свои папки-источники, которые сервер удалил (мягко, их можно вернуть restore)
    let removed: [String]

    private enum K: String, CodingKey { case canEdit, folders, id, removed }
    private struct Row: Decodable {
        let folder: LeadFolder?
        private enum RK: String, CodingKey { case id, folderId, name, keys, leadIds }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: RK.self)
            let num: Int? = c.flexInt(.folderId) ?? Int((c.str(.id) ?? "").replacingOccurrences(of: "f:", with: ""))
            guard let num else { folder = nil; return }
            let keys: [String] = ((try? c.decodeIfPresent([String].self, forKey: .keys)) ?? nil) ?? []
            let leads: [Int] = ((try? c.decodeIfPresent([Int].self, forKey: .leadIds)) ?? nil) ?? []
            folder = LeadFolder(id: String(num), name: c.str(.name) ?? "", keys: keys, leadIds: leads)
        }
    }

    init(canEdit: Bool, folders: [LeadFolder], newId: String? = nil, removed: [String] = []) {
        self.canEdit = canEdit; self.folders = folders; self.newId = newId; self.removed = removed
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        canEdit = c.bool(.canEdit) ?? true
        let rows: [Row] = ((try? c.decodeIfPresent([Row].self, forKey: .folders)) ?? nil) ?? []
        folders = rows.compactMap { (r: Row) -> LeadFolder? in r.folder }
        newId = c.str(.id)
        removed = ((try? c.decodeIfPresent([String].self, forKey: .removed)) ?? nil) ?? []
    }
}

/// Последняя копия папок с сервера на телефоне (по аккаунту) — для показа без сети.
private struct FolderCache: Codable {
    var folders: [LeadFolder]
    var canEdit: Bool
    var at: Date
}

@MainActor
@Observable
final class FolderStore {
    private(set) var folders: [LeadFolder] = []
    /// false — менеджер: папки владельца только на просмотр
    private(set) var canEdit = true
    /// сервер ответил в этом запуске (до этого — копия с телефона)
    private(set) var synced = false
    /// когда последний раз пришло состояние с сервера
    private(set) var syncedAt: Date?
    /// почему папки не загрузились (текст для показа)
    private(set) var loadError: String?
    @ObservationIgnored private var account = ""
    @ObservationIgnored private var loadedAccount: String?
    @ObservationIgnored private var refreshing = false
    /// растёт с каждой правкой: ответ GET, начатого до правки, не затирает её
    @ObservationIgnored private var gen = 0

    func load(account: String) {
        guard account != loadedAccount else { return }
        loadedAccount = account
        self.account = account
        synced = false
        loadError = nil
        if let d = UserDefaults.standard.data(forKey: cacheKey), let c = try? JSONDecoder().decode(FolderCache.self, from: d) {
            folders = c.folders; canEdit = c.canEdit; syncedAt = c.at
        } else {
            folders = []; canEdit = true; syncedAt = nil
        }
    }

    private var cacheKey: String { "povod.folders.server:" + account.lowercased() }
    /// папки прежних версий (только на телефоне) — источник для разового импорта; ключ не удаляем (запасная копия)
    private var legacyKey: String { "leadFolders:" + account.lowercased() }
    private var importedKey: String { "povod.folders.imported:" + account.lowercased() }

    private func save() {
        let c = FolderCache(folders: folders.filter { Int($0.id) != nil }, canEdit: canEdit, at: syncedAt ?? .now)
        if let d = try? JSONEncoder().encode(c) { UserDefaults.standard.set(d, forKey: cacheKey) }
    }

    private func legacyFolders() -> [LeadFolder] {
        guard let d = UserDefaults.standard.data(forKey: legacyKey), let f = try? JSONDecoder().decode([LeadFolder].self, from: d) else { return [] }
        return f
    }

    private func apply(_ s: FoldersState) {
        withAnimation(.spring(response: 0.3)) { folders = s.folders }
        canEdit = s.canEdit
        synced = true
        syncedAt = .now
        loadError = nil
        save()
    }

    /// Загрузить с сервера; при первом запуске новой версии — один раз перенести туда папки с телефона.
    func refresh(fixture: Bool) async {
        if fixture || refreshing { return }
        refreshing = true
        defer { refreshing = false }
        let acc: String = account
        let startGen: Int = gen
        do {
            var s: FoldersState = try await API.get(FoldersState.self, "/api/cabinet/folders/")
            if s.canEdit && !UserDefaults.standard.bool(forKey: importedKey) {
                let legacy: [LeadFolder] = legacyFolders()
                if !legacy.isEmpty {
                    let payload: [[String: Any]] = legacy.map { (f: LeadFolder) -> [String: Any] in
                        ["name": f.name, "keys": f.keys, "leadIds": f.leadIds]
                    }
                    s = try await API.post(FoldersState.self, "/api/cabinet/folders/import/", json: ["folders": payload])
                }
                // флаг — только после успешного ответа: при ошибке повторим в следующий раз (импорт идемпотентный)
                UserDefaults.standard.set(true, forKey: "povod.folders.imported:" + acc.lowercased())
            }
            // за время запроса сменился аккаунт или была правка — этот ответ устарел
            guard acc == account, startGen == gen else { return }
            apply(s)
        } catch {
            if acc == account { loadError = friendly(error) }
        }
    }

    /// Почему сейчас нельзя менять папки (nil — можно).
    var blockReason: String? {
        if !canEdit { return String(localized: "папки меняет владелец аккаунта — менеджеру они доступны только для просмотра") }
        if !NetMonitor.shared.online { return String(localized: "нет сети — папки можно будет менять, когда связь вернётся") }
        if !synced {
            if let e = loadError { return String(localized: "папки не загрузились с сервера: \(e)") }
            return String(localized: "папки ещё загружаются с сервера — подождите пару секунд")
        }
        return nil
    }

    static func segKey(_ l: Lead) -> String { (l.niche + "|" + l.city).lowercased() }

    /// номер своей папки на сервере: "f:12" → 12 (для ещё не сохранённой папки — nil)
    static func number(_ viewId: String) -> Int? {
        guard viewId.hasPrefix("f:") else { return nil }
        return Int(viewId.dropFirst(2))
    }

    func folder(_ viewId: String) -> LeadFolder? { folders.first { "f:" + $0.id == viewId } }

    /// в какой папке лид: ручной перенос → своя папка с его подборкой → папка подборки
    func folderId(_ l: Lead) -> String {
        if let f = folders.first(where: { $0.leadIds.contains(l.id) }) { return "f:" + f.id }
        let k = Self.segKey(l)
        if let f = folders.first(where: { $0.keys.contains(k) }) { return "f:" + f.id }
        return "k:" + k
    }

    /// своя папка, куда лид перенесён вручную (nil — лид там, куда ведёт его подборка)
    func manualFolderId(_ l: Lead) -> String? {
        folders.first(where: { $0.leadIds.contains(l.id) }).map { "f:" + $0.id }
    }

    func views(_ leads: [Lead]) -> [FolderView] {
        var count: [String: Int] = [:]
        var title: [String: String] = [:]
        for l in leads {
            let id = folderId(l)
            count[id, default: 0] += 1
            if id.hasPrefix("k:"), title[id] == nil { title[id] = "\(l.niche) · \(l.city)" }
        }
        var out = folders.map { FolderView(id: "f:" + $0.id, name: $0.name, count: count["f:" + $0.id] ?? 0, custom: true) }
        let auto = count.keys.filter { $0.hasPrefix("k:") }.map { FolderView(id: $0, name: title[$0] ?? $0, count: count[$0] ?? 0, custom: false) }
        out += auto.sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
        return out
    }

    // MARK: - правки через API

    /// Правка на сервере: сразу меняем у себя, ответ сервера заменяет копию; ошибка — откат и исключение с причиной.
    private func mutate(_ path: String, _ body: [String: Any], local: () -> Void) async throws -> FoldersState {
        if let why = blockReason { throw APIError(status: 0, message: why) }
        gen += 1
        let myGen: Int = gen
        let acc: String = account
        let before: [LeadFolder] = folders
        withAnimation(.spring(response: 0.3)) { local() }
        do {
            let s: FoldersState = try await API.post(FoldersState.self, path, json: body)
            if acc == account { apply(s) }
            return s
        } catch {
            if acc == account {
                if myGen == gen {
                    withAnimation(.spring(response: 0.3)) { folders = before }
                } else {
                    // после этой правки были другие — откат к старому снимку стёр бы их, берём состояние с сервера
                    Task { await self.refresh(fixture: false) }
                }
                if let e = error as? APIError, e.status == 403 { canEdit = false }
            }
            throw error
        }
    }

    private func requireNumber(_ viewId: String) throws -> Int {
        guard let n = Self.number(viewId) else { throw APIError(status: 0, message: String(localized: "папка ещё сохраняется — попробуйте через секунду")) }
        return n
    }

    /// новая папка → id "f:N"
    @discardableResult
    func create(_ name: String) async throws -> String {
        let tmp = LeadFolder(id: "tmp-" + UUID().uuidString, name: name, keys: [], leadIds: [])
        let s = try await mutate("/api/cabinet/folders/", ["name": name]) { folders.insert(tmp, at: 0) }
        return s.newId ?? ""
    }

    func rename(_ viewId: String, _ name: String) async throws {
        let n = try requireNumber(viewId)
        _ = try await mutate("/api/cabinet/folders/\(n)/rename/", ["name": name]) {
            if let i = folders.firstIndex(where: { "f:" + $0.id == viewId }) { folders[i].name = name }
        }
    }

    /// удалить свою папку (лиды вернутся в папки своих подборок) → номер для «отменить»
    func remove(_ viewId: String) async throws -> Int {
        let n = try requireNumber(viewId)
        _ = try await mutate("/api/cabinet/folders/\(n)/delete/", [:]) { folders.removeAll { "f:" + $0.id == viewId } }
        return n
    }

    /// вернуть удалённую папку (сервер хранит сутки)
    func restore(_ n: Int, local: LeadFolder?) async throws {
        _ = try await mutate("/api/cabinet/folders/\(n)/restore/", [:]) {
            if let f = local, !folders.contains(where: { $0.id == f.id }) { folders.insert(f, at: 0) }
        }
    }

    /// объединить папки в одну новую: подборки и ручные лиды переходят в неё, свои папки-источники сервер удаляет
    func merge(_ ids: [String], name: String) async throws -> (newId: String, removed: [String]) {
        for id in ids where id.hasPrefix("f:") { _ = try requireNumber(id) }
        let tmpId = "tmp-" + UUID().uuidString
        let s = try await mutate("/api/cabinet/folders/merge/", ["ids": ids, "name": name]) {
            var keys: [String] = [], leadIds: [Int] = []
            for id in ids {
                if id.hasPrefix("k:") { keys.append(String(id.dropFirst(2))) }
                if let f = folders.first(where: { "f:" + $0.id == id }) { keys += f.keys; leadIds += f.leadIds }
            }
            folders.removeAll { ids.contains("f:" + $0.id) }
            folders.insert(LeadFolder(id: tmpId, name: name, keys: Array(Set(keys)), leadIds: Array(Set(leadIds))), at: 0)
        }
        return (s.newId ?? "", s.removed)
    }

    /// «отменить» объединение: удалить общую папку и вернуть свои папки-источники
    func undoMerge(newId: String, removed: [String]) async throws {
        if Self.number(newId) != nil { _ = try await remove(newId) }
        for id in removed {
            if let n = Self.number(id) { try await restore(n, local: nil) }
        }
    }

    /// перенести компании: в свою папку ("f:N") — вручную; в папку подборки ("k:…") или "" — снять ручной перенос
    func move(_ leadIds: [Int], to viewId: String) async throws {
        let target: Any = Self.number(viewId).map { (n: Int) -> Any in "f:\(n)" } ?? NSNull()
        if viewId.hasPrefix("f:") { _ = try requireNumber(viewId) }
        _ = try await mutate("/api/cabinet/folders/move/", ["leadIds": leadIds, "to": target]) {
            for i in folders.indices { folders[i].leadIds.removeAll { leadIds.contains($0) } }
            if let i = folders.firstIndex(where: { "f:" + $0.id == viewId }) { folders[i].leadIds += leadIds }
        }
    }

    /// добавить/убрать компании своей папки (добавленные уходят из других папок)
    func setLeads(_ viewId: String, add: [Int], remove: [Int]) async throws {
        let n = try requireNumber(viewId)
        _ = try await mutate("/api/cabinet/folders/\(n)/leads/", ["add": add, "remove": remove]) {
            if !add.isEmpty { for i in folders.indices { folders[i].leadIds.removeAll { add.contains($0) } } }
            if let i = folders.firstIndex(where: { "f:" + $0.id == viewId }) {
                folders[i].leadIds.removeAll { remove.contains($0) }
                folders[i].leadIds += add
            }
        }
    }

    /// снимок 22 (-fixture): папки «как с сервера»
    func fixtureFill() {
        folders = [
            LeadFolder(id: "12", name: "Кофейни и пекарни", keys: ["кофейни|казань", "пекарни|казань"], leadIds: []),
            LeadFolder(id: "7", name: "Позвонить на неделе", keys: [], leadIds: [3]),
        ]
        canEdit = true
        synced = true
        syncedAt = .now
    }
}

extension Store {
    /// Правка папок в фоне: ошибка — тост с причиной (сама правка уже откатилась в FolderStore).
    func folderTask(_ work: @escaping @MainActor () async throws -> Void) {
        Task { @MainActor in
            do { try await work() } catch { self.show(friendly(error), ok: false) }
        }
    }

    /// Перенести компании в папку (из карточки и из «ещё»), с «отменить».
    func moveLeads(_ leads: [Lead], to v: FolderView) {
        if let why = folders.blockReason { show(why, ok: false); return }
        guard let first = leads.first else { return }
        let ids: [Int] = leads.map { $0.id }
        // «отменить» возвращает в папку первой компании (сейчас переносится всегда одна)
        let back: String = folders.manualFolderId(first) ?? ""
        let name: String = v.name
        folderTask {
            try await self.folders.move(ids, to: v.id)
            self.show(String(localized: "перенесено в «\(name)»"), undo: {
                self.folderTask { try await self.folders.move(ids, to: back) }
            }, undoSeconds: Guide.undoSeconds)
        }
    }

    /// Убрать компанию из своей папки, куда она перенесена вручную (вернётся в папку подборки).
    func removeLeadFromFolder(_ l: Lead) {
        if let why = folders.blockReason { show(why, ok: false); return }
        guard let fid = folders.manualFolderId(l) else { return }
        folderTask {
            try await self.folders.setLeads(fid, add: [], remove: [l.id])
            self.show(String(localized: "компания убрана из папки"), undo: {
                self.folderTask { try await self.folders.setLeads(fid, add: [l.id], remove: []) }
            }, undoSeconds: Guide.undoSeconds)
        }
    }
}

/// Выпадающий список папок над лидами.
struct FolderMenu: View {
    let views: [FolderView]
    let total: Int
    @Binding var selected: String?
    let onSettings: () -> Void

    private var title: String { views.first { $0.id == selected }?.name ?? String(localized: "все папки") }

    var body: some View {
        Menu {
            Button { selected = nil } label: { Label("все папки · \(total)", systemImage: selected == nil ? "checkmark" : "tray.full") }
            Divider()
            ForEach(views) { v in
                Button { selected = v.id } label: {
                    Label("\(v.name) · \(v.count)", systemImage: selected == v.id ? "checkmark" : (v.custom ? "folder.fill" : "folder"))
                }
            }
            Divider()
            Button(action: onSettings) { Label("настроить папки", systemImage: "slider.horizontal.3") }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selected == nil ? "tray.full" : "folder.fill").iconFont(14, .semibold)
                Text(title).font(Typo.body(15, .semibold)).lineLimit(2)
                Text("\(views.first { $0.id == selected }?.count ?? total)").font(Typo.mono(12, .medium)).opacity(0.55)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").iconFont(12, .bold).opacity(0.6)
            }
            .foregroundStyle(Pal.ink)
            .padding(.horizontal, 14).frame(minHeight: 44)
            .glassCapsule()
        }
    }
}

/// Настройки папок: объединить, переименовать, создать, удалить. Всё — на сервере (общие с сайтом).
struct FoldersSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let folders: FolderStore
    @Binding var selected: String?
    @State private var picked: Set<String> = []
    @State private var naming: Naming?
    @State private var name = ""
    @State private var deleting: FolderView?

    enum Naming: Identifiable { case merge, create, rename(String); var id: String { switch self { case .merge: return "m"; case .create: return "c"; case .rename(let i): return "r" + i } } }

    private var editable: Bool { folders.blockReason == nil }

    var body: some View {
        let views: [FolderView] = folders.views(store.leads)
        NavigationStack {
            List {
                statusSection
                Section {
                    ForEach(views) { (v: FolderView) in row(v) }
                } footer: {
                    Text(editable ? "Отметьте две и больше папки и нажмите «объединить». Свою папку можно переименовать или удалить: смахните её влево. Компании из удалённой папки вернутся в папки своих подборок. Папки общие с веб-кабинетом." : "Папки общие с веб-кабинетом. Менять их сейчас нельзя — причина выше.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(MetalBackground(star: .none).ignoresSafeArea())
            .refreshable { await folders.refresh(fixture: store.fixture) }
            .navigationTitle("папки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("готово") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { tapCreate() } label: { Label("новая", systemImage: "folder.badge.plus").labelStyle(.titleAndIcon) }
                        .accessibilityLabel(Text("новая папка"))
                        .disabled(!editable)
                }
                ToolbarItem(placement: .bottomBar) { mergeButton(views) }
            }
            .alert(namingTitle, isPresented: namingShown) {
                TextField("название", text: $name)
                Button("отмена", role: .cancel) {}
                Button("сохранить") { applyNaming() }
            }
            .alert("Удалить папку «\(deleting?.name ?? "")»?", isPresented: deletingShown) {
                Button("удалить", role: .destructive) { removeFolder() }
                Button("отмена", role: .cancel) {}
            } message: { Text("Компании не удалятся — вернутся в папки своих подборок.") }
        }
        .presentationDragIndicator(.visible)
        .task { await folders.refresh(fixture: store.fixture) }
    }

    // заголовок и Binding диалогов — отдельными свойствами с явными типами (не внутри длинной цепочки модификаторов)
    private var namingTitle: String {
        guard let n = naming else { return "" }
        return alertTitle(n)
    }
    private var namingShown: Binding<Bool> {
        Binding<Bool>(get: { naming != nil }, set: { (v: Bool) in if !v { naming = nil } })
    }
    private var deletingShown: Binding<Bool> {
        Binding<Bool>(get: { deleting != nil }, set: { (v: Bool) in if !v { deleting = nil } })
    }

    /// откуда папки и можно ли их менять
    @ViewBuilder private var statusSection: some View {
        if let why = folders.blockReason {
            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: folders.canEdit ? "wifi.slash" : "lock").iconFont(15, .semibold).foregroundStyle(Pal.fg2)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(why).font(Typo.body(14, .semibold)).foregroundStyle(Pal.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let t = syncedText { Text(t).font(Typo.body(13)).foregroundStyle(Pal.fg2) }
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var syncedText: String? {
        guard let d = folders.syncedAt else { return nil }
        let when: String = d.formatted(date: .abbreviated, time: .shortened)
        return String(localized: "показана копия с сервера от \(when)")
    }

    private func row(_ v: FolderView) -> some View {
        let on: Bool = picked.contains(v.id)
        return HStack(spacing: 12) {
            if editable {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .iconFont(20).foregroundStyle(on ? Pal.ink : Pal.ink.opacity(0.3))
                    .accessibilityHidden(true)
            }
            Image(systemName: v.custom ? "folder.fill" : "folder").foregroundStyle(Pal.ink.opacity(0.7)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(v.name).font(Typo.body(15)).foregroundStyle(Pal.ink)
                Text(v.custom ? "своя папка · \(v.count)" : "подборка · \(v.count)").font(Typo.body(13)).foregroundStyle(Pal.fg2)
            }
            Spacer()
            if v.custom && FolderStore.number(v.id) == nil {
                ProgressView().accessibilityLabel(Text("сохраняется"))
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture {
            guard editable else { return }
            haptic()
            if on { picked.remove(v.id) } else { picked.insert(v.id) }
        }
        .accessibilityAddTraits(on ? AccessibilityTraits([.isButton, .isSelected]) : AccessibilityTraits.isButton)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if v.custom && editable && FolderStore.number(v.id) != nil {
                Button(role: .destructive) { deleting = v } label: { Label("удалить", systemImage: "trash") }
                Button { name = v.name; naming = .rename(v.id) } label: { Label("имя", systemImage: "pencil") }.tint(Pal.fg2)
            }
        }
    }

    private func mergeButton(_ views: [FolderView]) -> some View {
        let ready: Bool = picked.count >= 2 && editable
        return Button {
            name = mergeName(views); naming = .merge
        } label: {
            Text(picked.count >= 2 ? "объединить \(picked.count)" : "отметьте 2 папки, чтобы объединить").font(Typo.body(16, .semibold))
                .frame(maxWidth: .infinity).frame(minHeight: 46)
                .foregroundStyle(ready ? Pal.onInk : Pal.ink.opacity(0.35))
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ready ? Pal.ink : Pal.ink.opacity(0.06)))
        }
        .disabled(!ready)
    }

    private func tapCreate() {
        if let why = folders.blockReason { store.show(why, ok: false); return }
        name = ""; naming = .create
    }

    private func alertTitle(_ n: Naming) -> String {
        switch n {
        case .merge: return String(localized: "Название общей папки")
        case .create: return String(localized: "Новая папка")
        case .rename: return String(localized: "Новое название")
        }
    }

    /// «автосервисы» для «автосервисы · Екатеринбург» + «автосервисы · Пермь»
    private func mergeName(_ views: [FolderView]) -> String {
        let names = views.filter { picked.contains($0.id) }.map { $0.name.components(separatedBy: " · ").first ?? $0.name }
        return Set(names).count == 1 ? (names.first ?? "") : ""
    }

    private func applyNaming() {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let mode = naming else { return }
        naming = nil
        guard !n.isEmpty else { store.show(String(localized: "назовите папку"), ok: false); return }
        guard n.count <= 80 else { store.show(String(localized: "название папки — до 80 знаков"), ok: false); return }
        if let why = folders.blockReason { store.show(why, ok: false); return }
        let fs: FolderStore = folders
        let st: Store = store
        switch mode {
        case .merge:
            let ids: [String] = Array(picked)
            let wasSelected: Bool = selected.map { ids.contains($0) } ?? false
            picked = []
            let sel: Binding<String?> = $selected
            st.folderTask {
                let r = try await fs.merge(ids, name: n)
                if wasSelected && !r.newId.isEmpty { sel.wrappedValue = r.newId }
                st.show(String(localized: "папки объединены в «\(n)»"), undo: {
                    st.folderTask {
                        try await fs.undoMerge(newId: r.newId, removed: r.removed)
                        if sel.wrappedValue == r.newId { sel.wrappedValue = nil }
                        st.show(String(localized: "объединение отменено"))
                    }
                }, undoSeconds: Guide.undoSeconds)
            }
        case .create:
            st.folderTask {
                try await fs.create(n)
                st.show(String(localized: "папка «\(n)» создана"))
            }
        case .rename(let id):
            st.folderTask { try await fs.rename(id, n) }
        }
    }

    private func removeFolder() {
        guard let v = deleting else { return }
        deleting = nil
        if let why = folders.blockReason { store.show(why, ok: false); return }
        let local: LeadFolder? = folders.folder(v.id)
        if selected == v.id { selected = nil }
        picked.remove(v.id)
        let fs: FolderStore = folders
        let st: Store = store
        let name: String = v.name
        st.folderTask {
            let n = try await fs.remove(v.id)
            st.show(String(localized: "папка «\(name)» удалена"), undo: {
                st.folderTask {
                    try await fs.restore(n, local: local)
                    st.show(String(localized: "папка «\(name)» вернулась"))
                }
            }, undoSeconds: Guide.undoSeconds)
        }
    }
}
