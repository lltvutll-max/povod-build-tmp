import SwiftUI

struct LeadsView: View {
    @Environment(Store.self) private var store
    @State private var q = ""
    @State private var reasonF = "all"
    /// сайт: all / yes / no
    @State private var siteF = "all"
    /// папка = подборка «ниша · город» (ключ в нижнем регистре); nil — все компании
    @State private var folder: String?
    @State private var folderSettings = false
    @State private var filterSheet = false
    /// «ещё ⋯» из свайпа и выбор папки для одной компании
    @State private var moreLead: Lead?
    @State private var folderPickLead: Lead?
    @State private var searchTask: Task<Void, Never>?
    @State private var share: ShareFile?
    @AppStorage(Guide.hintLeads) private var hintSeen = false

    static let statusTabs: [(String, String)] = [("all", String(localized: "все")), ("new", String(localized: "новые")), ("written", String(localized: "связались")), ("answered", String(localized: "ответили")), ("deal", String(localized: "сделка")), ("refused", String(localized: "отказ"))]

    private func visible() -> [Lead] {
        let sf = store.segmentFilter
        let query = q.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "ё", with: "е")
        var list = store.leads.filter { l in
            if store.leadFilter != "all" && l.status != store.leadFilter { return false }
            if reasonF != "all" && Reason.code(l) != reasonF { return false }
            if siteF != "all" && (siteF == "yes") != !(l.site ?? "").isEmpty { return false }
            if let sf, l.city.lowercased() != sf.city.lowercased() || l.niche.lowercased() != sf.niche.lowercased() { return false }
            if let folder, store.folders.folderId(l) != folder { return false }
            if !query.isEmpty {
                let hay = (l.name + " " + l.city + " " + l.niche).lowercased().replacingOccurrences(of: "ё", with: "е")
                if !hay.contains(query) { return false }
            }
            return true
        }
        list.sort { a, b in
            if a.st.order != b.st.order { return a.st.order < b.st.order }
            return (a.date ?? .distantPast) > (b.date ?? .distantPast)
        }
        return list
    }

    static func key(_ l: Lead) -> String { (l.niche + "|" + l.city).lowercased() }

    /// сколько фильтров включено (статус, повод, сайт)
    private var filterCount: Int {
        var n = 0
        if store.leadFilter != "all" { n += 1 }
        if reasonF != "all" { n += 1 }
        if siteF != "all" { n += 1 }
        return n
    }

    // Тело разбито на слои с явными типами (длинная цепочка из 13 модификаторов с замыканиями — риск
    // «unable to type-check this expression in reasonable time»). Порядок модификаторов прежний.
    var body: some View {
        let list: [Lead] = visible()
        selectionLayer(sheetsLayer(mainLayer(list)))
    }

    /// для `$store.…` вне body (как `@Bindable var store = store`)
    private var bindable: Bindable<Store> { Bindable(store) }

    /// шапка, поиск, папки, фильтр, список + загрузка папок
    private func mainLayer(_ list: [Lead]) -> some View {
        VStack(spacing: 0) {
            if store.leadSelecting { selectHeader(list) } else { header }
            searchField
            HStack(spacing: 8) {
                FolderMenu(views: store.folders.views(store.leads), total: store.leads.count, selected: $folder) { folderSettings = true }
                filterButton
            }
            .padding(.horizontal, 16).padding(.top, 10)
            if filterCount > 0 { filterSummary }
            leadList(list)
        }
        .metalBackground(.corner)
        .onAppear {
            store.folders.load(account: store.user?.email ?? "")
            takeSegmentFilter()
            if store.fixture && store.fixtureMail == "folders" { folderSettings = true }
            if store.fixture && store.fixtureMail == "folders-server" { store.folders.fixtureFill(); folderSettings = true }
            if store.fixture && store.fixtureMail == "filter" { filterSheet = true }
        }
        .task {
            store.folders.load(account: store.user?.email ?? "")
            // переключение вкладок: свежее минуты не трогаем; компании — тоже (копия уже на экране)
            await store.loadLeads(force: false)
            await store.folders.refresh(fixture: store.fixture, force: false)
        }
    }

    /// листы папок и фильтра, перенос одной компании, «ещё ⋯»
    private func sheetsLayer<V: View>(_ content: V) -> some View {
        content
        .sheet(isPresented: $folderSettings) { FoldersSheet(folders: store.folders, selected: $folder) }
        .sheet(isPresented: $filterSheet) { LeadsFilterSheet(status: bindable.leadFilter, reason: $reasonF, site: $siteF) }
        .sheet(item: $folderPickLead) { (l: Lead) in LeadFolderPicker(lead: l) }
        .confirmationDialog(moreTitle, isPresented: moreShown, titleVisibility: .visible, presenting: moreLead) { (l: Lead) in
            Button("перенести в папку…") { folderPickLead = l }
            Button("выбрать несколько") { store.startLeadSelecting(l.id) }
            if store.user?.isManager != true {
                Button("удалить из кабинета", role: .destructive) { store.deleteLead(l.id) }
            }
            Button("отмена", role: .cancel) {}
        } message: { (_: Lead) in
            Text("после удаления 9 секунд можно нажать «отменить»")
        }
    }

    /// режим выбора: панель, листы «в рассылку» / «в Sguardo» / «поделиться», подтверждение удаления
    private func selectionLayer<V: View>(_ content: V) -> some View {
        content
        .overlay(alignment: .bottom) {
            if store.leadSelecting {
                LeadSelectionBar(share: $share)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: bindable.leadMailSheet) { LeadsMailSheet(ids: store.selectedLeadIds()) }
        .sheet(isPresented: bindable.leadSguardoSheet) { LeadsSguardoSheet(ids: store.selectedLeadIds()) }
        .sheet(item: $share) { (f: ShareFile) in
            ActivityView(items: [f.url]).presentationDetents([.medium, .large]).ignoresSafeArea()
        }
        .alert(deleteTitle, isPresented: bindable.leadConfirmDelete) {
            Button("убрать", role: .destructive) {
                let ids: Set<Int> = Set(store.selectedLeadIds())
                store.stopLeadSelecting()
                store.bulkDelete(ids)
            }
            Button("отмена", role: .cancel) {}
        } message: {
            Text("они останутся в истории и повторно не придут. 9 секунд можно отменить")
        }
        .onChange(of: store.segmentFilter) { _, _ in takeSegmentFilter() }
    }

    private var moreTitle: String { moreLead?.name ?? "" }
    private var moreShown: Binding<Bool> {
        Binding<Bool>(get: { moreLead != nil }, set: { (v: Bool) in if !v { moreLead = nil } })
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").iconFont(15).foregroundStyle(Pal.ink.opacity(0.6)).accessibilityHidden(true)
            TextField("", text: $q, prompt: Text("поиск по названию и городу").foregroundColor(Pal.fg3))
                .font(Typo.body(16)).foregroundStyle(Pal.ink)
                .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                .accessibilityLabel(Text("поиск компаний"))
                .onChange(of: q) { _, v in
                    // по загруженным ищем сразу, по всему кабинету — на сервере (через полсекунды тишины)
                    searchTask?.cancel()
                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        if Task.isCancelled { return }
                        await store.loadLeads(query: v.trimmingCharacters(in: .whitespaces))
                    }
                }
            if !q.isEmpty {
                Button { q = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Pal.fg3).frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(Text("очистить поиск"))
            }
        }
        .padding(.horizontal, 14).frame(minHeight: 44)
        .glassCapsule()
        .padding(.horizontal, 16).padding(.top, 14)
    }

    private var filterButton: some View {
        let n: Int = filterCount
        return Button { haptic(); filterSheet = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease").iconFont(14, .semibold)
                Text(n > 0 ? "фильтр (\(n))" : "фильтр").font(Typo.body(15, .semibold)).lineLimit(1)
            }
            .foregroundStyle(n > 0 ? Pal.onInk : Pal.ink)
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(Capsule().fill(n > 0 ? Pal.ink : Pal.surface.opacity(0.6)))
            .overlay(Capsule().stroke(Pal.surface.opacity(n > 0 ? 0 : 0.9), lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .fixedSize()
        .accessibilityLabel(Text(n > 0 ? "фильтр, включено: \(n)" : "фильтр"))
    }

    /// что сейчас отфильтровано — словами, со сбросом
    private var filterSummary: some View {
        var parts: [String] = []
        if let t = Self.statusTabs.first(where: { $0.0 == store.leadFilter && $0.0 != "all" }) { parts.append(t.1) }
        if reasonF != "all" { parts.append(Reason.short[reasonF] ?? reasonF) }
        if siteF == "yes" { parts.append(String(localized: "есть сайт")) }
        if siteF == "no" { parts.append(String(localized: "без сайта")) }
        let line: String = parts.joined(separator: " · ")
        return HStack(spacing: 8) {
            Text("показаны: \(line)").font(Typo.body(14)).foregroundStyle(Pal.fg2).lineLimit(2)
            Spacer(minLength: 4)
            Button { haptic(); withAnimation(.spring(response: 0.3)) { resetFilters(keepSearch: true) } } label: {
                Text("сбросить").font(Typo.body(14, .semibold)).foregroundStyle(Pal.ink)
                    .padding(.horizontal, 6).frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }

    private func resetFilters(keepSearch: Bool = false) {
        store.leadFilter = "all"
        reasonF = "all"
        siteF = "all"
        if !keepSearch { q = ""; folder = nil }
    }

    private func leadList(_ list: [Lead]) -> some View {
        List {
            if let e = store.lastError, !store.leads.isEmpty {
                StaleNote(why: e).modifier(LeadRowStyle(top: 6))
            }
            if !hintSeen && Guide.hintsAllowed && !store.leadSelecting && !store.leads.isEmpty {
                HintCard(key: Guide.hintLeads, icon: "hand.draw",
                         title: String(localized: "как работать со списком"),
                         text: String(localized: "Смахните компанию вправо — «связались», влево — «отказ» и «ещё». Удержание — выбрать несколько компаний сразу. «Фильтр» — статусы, поводы и сайт."))
                    .modifier(LeadRowStyle(top: 6))
            }
            ForEach(list) { (l: Lead) in
                LeadCard(lead: l, selecting: store.leadSelecting, picked: store.leadSelected.contains(l.id), onLongPress: {
                    if store.leadSelecting {
                        withAnimation(.spring(response: 0.25)) { store.toggleLeadSelected(l.id) }
                    } else {
                        store.startLeadSelecting(l.id)
                    }
                }) {
                    if store.leadSelecting {
                        withAnimation(.spring(response: 0.25)) { store.toggleLeadSelected(l.id) }
                    } else {
                        store.open(.lead(l.id))
                    }
                }
                .modifier(LeadRowStyle(top: 4))
                .swipeActions(edge: .leading, allowsFullSwipe: true) { leadingSwipe(l) }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) { trailingSwipe(l) }
            }
            if list.isEmpty {
                emptyView.modifier(LeadRowStyle(top: 10))
            }
            if store.leadsTotal > store.leads.count {
                Text("показаны \(store.leads.count) свежих из \(Fmt.num(store.leadsTotal)) — поиск ищет по всем")
                    .font(Typo.body(13)).foregroundStyle(Pal.fg3)
                    .frame(maxWidth: .infinity)
                    .modifier(LeadRowStyle(top: 8))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        .contentMargins(.top, 6, for: .scrollContent)
        .contentMargins(.bottom, 130, for: .scrollContent)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: store.leadFilter)
        .refreshable {
            await store.loadLeads(query: q)
            await store.folders.refresh(fixture: store.fixture)
        }
    }

    /// вправо: «связались» (полный свайп), у «связались» — вернуть в новые
    @ViewBuilder private func leadingSwipe(_ l: Lead) -> some View {
        if !store.leadSelecting {
            if l.st == .written {
                Button { swipeStatus(l, .new) } label: { Label("в новые", systemImage: "arrow.uturn.backward") }
                    .tint(Color(hex: 0x6A6662))
            } else {
                Button { swipeStatus(l, .written) } label: { Label("связались", systemImage: "checkmark") }
                    .tint(Color(hex: 0x1F7A4D))
            }
        }
    }

    /// влево: «отказ» и «ещё ⋯» (в папку, выбрать, удалить с отменой)
    @ViewBuilder private func trailingSwipe(_ l: Lead) -> some View {
        if !store.leadSelecting {
            if l.st == .refused {
                Button { swipeStatus(l, .new) } label: { Label("в новые", systemImage: "arrow.uturn.backward") }
                    .tint(Color(hex: 0x6A6662))
            } else {
                Button { swipeStatus(l, .refused) } label: { Label("отказ", systemImage: "hand.raised") }
                    .tint(Color(hex: 0x8A8782))
            }
            Button { moreLead = l } label: { Label("ещё", systemImage: "ellipsis.circle") }
                .tint(Color(hex: 0x3A3633))
        }
    }

    private func swipeStatus(_ l: Lead, _ st: LeadStatus) {
        haptic(.medium)
        Task { await store.setStatus(l.id, st) }
    }

    @ViewBuilder private var emptyView: some View {
        if store.firstLoading || (store.loading && store.leads.isEmpty && store.lastError == nil) {
            SkeletonRows(count: 6, cards: true)
        } else if store.leads.isEmpty && q.isEmpty {
            EmptyState(icon: "building.2", title: String(localized: "компаний пока нет"),
                       text: String(localized: "Создайте подборку: ниша и город. Повод найдёт компании, которым есть повод написать, и подготовит каждой первое сообщение."),
                       action: String(localized: "собрать базу")) { store.open(.collect) }
        } else if store.leadFilter == "new" && reasonF == "all" && siteF == "all" && q.isEmpty && folder == nil {
            EmptyState(icon: "checkmark.circle", title: String(localized: "новых нет — все отработаны"),
                       text: String(localized: "Новые компании придут со следующей порцией. Пока можно вернуться к тем, с кем уже связались."),
                       action: String(localized: "показать все")) { store.leadFilter = "all" }
        } else {
            EmptyState(icon: "line.3.horizontal.decrease.circle", title: String(localized: "по фильтру ничего нет"),
                       text: String(localized: "Попробуйте другой фильтр, папку или запрос — или сбросьте всё."),
                       action: String(localized: "сбросить фильтр")) { withAnimation(.spring(response: 0.3)) { resetFilters() } }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 14) {
            Text("компании").font(Typo.display(30)).tracking(-1).foregroundStyle(Pal.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if !store.leads.isEmpty {
                Button { haptic(); store.startLeadSelecting() } label: {
                    Text("выбрать").font(Typo.body(15, .semibold)).foregroundStyle(Pal.ink)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
            PillButton(height: 34, action: { store.open(.collect) }) {
                Image(systemName: "plus").iconFont(14, .semibold)
                Text("собрать")
            }
            .accessibilityLabel(Text("собрать новые компании"))
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
    }

    /// шапка режима выбора: «выбрано: N», «выбрать все» (видимые в папке/фильтре), «готово»
    private func selectHeader(_ list: [Lead]) -> some View {
        let n: Int = store.leadSelected.count
        let visibleIds: Set<Int> = Set(list.map(\.id))
        let allOn: Bool = !visibleIds.isEmpty && visibleIds.isSubset(of: store.leadSelected)
        return HStack(alignment: .center, spacing: 6) {
            Text(n == 0 ? "выберите компании" : "выбрано: \(n)")
                .font(Typo.display(n == 0 ? 20 : 24)).tracking(-0.8).foregroundStyle(Pal.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Spacer(minLength: 4)
            Button {
                haptic()
                withAnimation(.spring(response: 0.25)) {
                    if allOn { store.leadSelected.subtract(visibleIds) } else { store.leadSelected.formUnion(visibleIds) }
                }
            } label: {
                Text(allOn ? "снять все" : "выбрать все").font(Typo.body(14, .semibold)).foregroundStyle(Pal.ink)
                    .padding(.horizontal, 8).frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .disabled(visibleIds.isEmpty)
            Button { haptic(); store.stopLeadSelecting() } label: {
                Text("готово").font(Typo.body(14, .semibold)).foregroundStyle(Pal.onInk)
                    .padding(.horizontal, 16).frame(minHeight: 36)
                    .background(Capsule().fill(Pal.ink))
                    .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
        }
        .padding(.leading, 20).padding(.trailing, 16)
        .padding(.top, 18)
    }

    private var deleteTitle: String {
        let n: Int = store.selectedLeadIds().count
        return String(localized: "Убрать \(n) компаний из кабинета?")
    }

    /// «подборка» с главного экрана открывается как папка
    private func takeSegmentFilter() {
        guard let sf = store.segmentFilter else { return }
        let k: String = (sf.niche + "|" + sf.city).lowercased()
        let segId: String = "k:" + k
        // по шагам (раньше — одно выражение из трёх замыканий и двух ??): папка подборки → папка, где её компании → ключ подборки
        let views: [FolderView] = store.folders.views(store.leads)
        if let v = views.first(where: { (x: FolderView) -> Bool in x.id == segId }) {
            folder = v.id
        } else if let l = store.leads.first(where: { (x: Lead) -> Bool in FolderStore.segKey(x) == k }) {
            folder = store.folders.folderId(l)
        } else {
            folder = segId
        }
        store.segmentFilter = nil
    }
}

/// Папка лидов: иконка, название подборки, число лидов.
struct FolderChip: View {
    let title: String
    let count: Int
    let on: Bool
    let action: () -> Void
    var body: some View {
        Button(action: { haptic(); action() }) {
            HStack(spacing: 6) {
                Image(systemName: on ? "folder.fill" : "folder").iconFont(13, .semibold)
                Text(title).font(Typo.body(13, .semibold)).lineLimit(1)
                Text("\(count)").font(Typo.mono(12, .medium)).opacity(0.6)
            }
            .foregroundStyle(on ? Pal.onInk : Pal.ink)
            .padding(.horizontal, 12).frame(minHeight: 34)
            .background {
                if on { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Pal.ink) }
                else { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Pal.surface.opacity(0.55)) }
            }
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Pal.surface.opacity(on ? 0 : 0.9), lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

struct StatusTag: View {
    let st: LeadStatus
    var body: some View {
        Text(st.title)
            .font(Typo.body(13, .semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(bg))
    }
    private var fg: Color {
        switch st {
        case .new, .answered: return Pal.onInk
        case .deal: return Pal.onInk
        case .refused: return Pal.fg2
        case .written: return Pal.ink
        }
    }
    private var bg: Color {
        switch st {
        case .new, .answered: return Pal.ink
        case .deal: return Pal.ok
        case .written: return Pal.ink.opacity(0.08)
        case .refused: return Pal.ink.opacity(0.05)
        }
    }
}

struct LeadCard: View {
    let lead: Lead
    var selecting = false
    var picked = false
    /// удержание строки — войти в режим выбора с ней
    var onLongPress: (() -> Void)? = nil
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        HStack(spacing: 12) {
            if selecting {
                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(picked ? Pal.ink : Pal.ink.opacity(0.35))
                    .transition(.scale.combined(with: .opacity))
            }
            card
        }
        .padding(.leading, selecting ? 4 : 0)
        .contentShape(Rectangle())
        .scaleEffect(pressed ? 0.98 : 1)
        .animation(.spring(response: 0.25), value: pressed)
        .onTapGesture { haptic(); action() }
        .onLongPressGesture(minimumDuration: 0.45, perform: {
            guard let onLongPress else { return }
            haptic(.medium)
            onLongPress()
        }, onPressingChanged: { (p: Bool) in pressed = p })
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(picked ? AccessibilityTraits([.isButton, .isSelected]) : AccessibilityTraits.isButton)
        .accessibilityAction(named: Text(selecting ? "отметить" : "выбрать несколько")) { onLongPress?() }
    }

    private var card: some View {
        let code = Reason.code(lead)
        return VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(lead.name).font(Typo.body(16, .semibold)).foregroundStyle(Pal.ink).lineLimit(2)
                    Spacer(minLength: 4)
                    StatusTag(st: lead.st)
                }
                Text(subtitle).font(Typo.body(14)).foregroundStyle(Pal.fg2).lineLimit(2)
                HStack(spacing: 8) {
                    Text(Reason.short[code] ?? code)
                        .font(Typo.body(13, .semibold)).foregroundStyle(Pal.ink)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Pal.surface.opacity(0.85)))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Pal.ink.opacity(0.15), lineWidth: 0.5))
                    if lead.power > 0 {
                        PowerBar(p: lead.power)
                        Text("шанс \(lead.power)/10").font(Typo.body(13)).foregroundStyle(Pal.fg2).accessibilityHidden(true)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassRect(22)
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Pal.ink.opacity(strokeOpacity), lineWidth: 1.5))
            .opacity(cardOpacity)
    }

    private var strokeOpacity: Double { selecting && picked ? 0.55 : 0 }

    private var cardOpacity: Double {
        let dim: Bool = lead.st == .written || lead.st == .refused
        if !dim { return 1 }
        return selecting && picked ? 0.8 : 0.55
    }

    private var subtitle: String {
        var parts: [String] = [capFirst(lead.city), lead.niche]
        if let r = lead.rating, r > 0 { parts.append(Fmt.rating(r) + " ★") }
        if let n = lead.reviews, n > 0 { parts.append(String(localized: "\(n) отз.")) }
        return joinParts(parts)
    }
}

/// Строка списка компаний: без разделителей и фона, отступы как у прежней ленты.
struct LeadRowStyle: ViewModifier {
    var top: CGFloat = 4
    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: top, leading: 16, bottom: 4, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
