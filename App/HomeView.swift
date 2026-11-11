import SwiftUI

struct HomeView: View {
    @Environment(Store.self) private var store
    @State private var openSignal: Signal?
    @State private var singleDelete: Int?

    var body: some View {
        let o = store.overview
        let newCount = store.leads.filter { $0.st == .new }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                StarLogo(size: 18).padding(.horizontal, 4)
                Text("как идут дела в этом месяце")
                    .font(Typo.display(26)).tracking(-0.9).lineSpacing(2).foregroundStyle(Pal.ink)
                    .frame(maxWidth: 290, alignment: .leading)
                    .padding(.horizontal, 4).padding(.top, 22)

                VStack(alignment: .leading, spacing: 0) {
                    Text("в работе у вас").font(Typo.body(14)).foregroundStyle(Pal.fg2)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Fmt.num(store.leadsTotal)).font(Typo.mono(44)).tracking(-1.7).foregroundStyle(Pal.ink)
                            .contentTransition(.numericText())
                        Text("компаний").font(Typo.body(16)).foregroundStyle(Pal.fg2)
                    }
                    .padding(.top, 4)
                    infoRow(String(localized: "тариф"), planLine(o))
                    infoRow(String(localized: "следующая порция компаний"), o.nextIssue?.when ?? "—")
                    if let l = o.limits, let lim = l.leads, lim > 0 {
                        infoRow(String(localized: "компаний по тарифу"), String(localized: "\(l.leadsUsed ?? 0) из \(lim)"))
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassRect(24)
                .padding(.top, 16)

                HStack(spacing: 8) {
                    tile(String(localized: "связались"), o.metrics.wrote) { store.leadFilter = LeadStatus.written.rawValue; store.tab = .leads }
                    tile(String(localized: "ответили"), o.metrics.answered) { store.leadFilter = LeadStatus.answered.rawValue; store.tab = .leads }
                    tile(String(localized: "новых"), newCount) { store.leadFilter = LeadStatus.new.rawValue; store.tab = .leads }
                }
                .padding(.top, 8)

                HintCard(key: Guide.hintHome, icon: "questionmark.circle",
                         title: String(localized: "что такое подборка и порция"),
                         text: String(localized: "Подборка — это поиск компаний: ниша и город, например «кофейни · Казань». Порция — новые компании из подборок, которые приходят по расписанию тарифа. Паузу подборки можно поставить в любой момент — лимит не тратится."))
                    .padding(.top, 14)
                segHeader
                if store.segSelecting { segQuickChips }
                VStack(spacing: 0) {
                    if store.segments.isEmpty {
                        EmptyState(icon: "magnifyingglass", title: String(localized: "подборок пока нет"),
                                   text: String(localized: "Подборка — поиск компаний по нише и городу. Создайте первую — и Повод начнёт присылать компании с готовыми сообщениями."),
                                   action: String(localized: "новая подборка")) { store.open(.collect) }
                    }
                    ForEach(Array(store.segments.enumerated()), id: \.element.id) { i, s in
                        segRow(s, first: i == 0)
                    }
                }
                .glassRect(24)
                if !store.segSelecting && store.segments.count > 1 {
                    Text("удержание подборки — пауза, удалить; «выбрать» — сразу несколько")
                        .font(Typo.body(13)).foregroundStyle(Pal.fg2).padding(.horizontal, 4).padding(.top, 8)
                }

                HStack {
                    Cap(String(localized: "сигналы — повод написать первым"))
                    Button { store.tab = .signals } label: { Text("все \(store.signals.count)").font(Typo.body(14, .semibold)).foregroundStyle(Pal.ink).padding(.top, 14) }
                }
                VStack(spacing: 8) {
                    if store.signals.isEmpty {
                        Text("сигналов пока нет — придут, когда у компаний из подборок что-то случится: упадёт сайт, появятся плохие отзывы")
                            .font(Typo.body(14)).foregroundStyle(Pal.fg2).frame(maxWidth: .infinity, alignment: .leading).padding(16).glassRect(24)
                    }
                    ForEach(store.signals.prefix(3)) { s in
                        SignalCard(signal: s) { store.markSeen(s.id); openSignal = s }
                    }
                }
                if let e = store.lastError {
                    Text("связь: \(e)").font(Typo.body(13)).foregroundStyle(Pal.fg3).frame(maxWidth: .infinity).padding(.top, 12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .padding(.bottom, 130)
        }
        .refreshable { await store.refreshAll() }
        .metalBackground(.corner)
        .sheet(item: $openSignal) { s in SignalSheet(signal: s) }
        .overlay(alignment: .bottom) {
            if store.segSelecting {
                SegmentSelectionBar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .confirmationDialog(deleteTitle, isPresented: confirmShown, titleVisibility: .visible) {
            Button("удалить", role: .destructive) {
                let ids: Set<Int> = deleteIds
                store.stopSegSelecting()
                singleDelete = nil
                store.deleteSegments(ids)
            }
            Button("отмена", role: .cancel) { singleDelete = nil }
        } message: {
            Text("уже выданные компании останутся в списке. 9 секунд можно отменить")
        }
    }

    private var confirmShown: Binding<Bool> {
        Binding<Bool>(get: { store.segConfirmDelete }, set: { (v: Bool) in store.segConfirmDelete = v })
    }

    /// что удаляем: одну подборку из меню или выбранные
    private var deleteIds: Set<Int> {
        if let one = singleDelete { return [one] }
        return store.segSelected
    }

    private var deleteTitle: String {
        let ids = deleteIds
        if ids.count == 1, let sg = store.segments.first(where: { ids.contains($0.id) }) {
            return String(localized: "удалить подборку «\(sg.niche) · \(sg.city)»?")
        }
        return String(localized: "удалить \(ids.count) подборок?")
    }

    private var segHeader: some View {
        HStack(spacing: 16) {
            if store.segSelecting {
                Cap(store.segSelected.isEmpty ? String(localized: "выберите подборки") : String(localized: "выбрано: \(store.segSelected.count) подборок"))
                Button { store.stopSegSelecting() } label: {
                    Text("готово").font(Typo.body(14, .semibold)).foregroundStyle(Pal.ink).padding(.top, 14)
                }
            } else {
                let active: Int = store.segments.filter(\.on).count
                Cap(String(localized: "подборки · \(active) активных"))
                if !store.segments.isEmpty {
                    Button { store.startSegSelecting() } label: {
                        Text("выбрать").font(Typo.body(14, .semibold)).foregroundStyle(Pal.ink).padding(.top, 14)
                    }
                }
                Button { store.open(.collect) } label: { Text("+ новая").font(Typo.body(14, .semibold)).foregroundStyle(Pal.ink).padding(.top, 14) }
            }
        }
    }

    /// быстрый выбор: заменяет текущий выбор
    private func quick(_ text: String, _ ids: [Int]) -> some View {
        let set = Set(ids)
        let on: Bool = !set.isEmpty && set == store.segSelected
        return Chip(text: text, count: "\(ids.count)", on: on, height: 32, fontSize: 13) {
            withAnimation(.spring(response: 0.3)) { store.segSelected = on ? [] : set }
        }
    }

    private var segQuickChips: some View {
        let all: [Int] = store.segments.map(\.id)
        let paused: [Int] = store.segments.filter { !$0.on }.map(\.id)
        let ended: [Int] = store.segments.filter { $0.exhausted }.map(\.id)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                quick(String(localized: "все"), all)
                quick(String(localized: "на паузе"), paused)
                quick(String(localized: "законченные"), ended)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .padding(.bottom, 10)
    }

    private func planLine(_ o: Overview) -> String {
        let name: String = o.planName ?? String(localized: "без тарифа")
        return o.plan == "owner" ? String(localized: "\(name) · владелец") : name
    }

    private func infoRow(_ l: String, _ v: String) -> some View {
        HStack(spacing: 10) {
            Text(l).foregroundStyle(Pal.fg2)
            Spacer()
            Text(v).font(Typo.body(13, .semibold)).foregroundStyle(Pal.ink).multilineTextAlignment(.trailing)
        }
        .font(Typo.body(13))
        .padding(.top, 8)
    }

    private func tile(_ label: String, _ n: Int, action: @escaping () -> Void) -> some View {
        Button { haptic(); action() } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(Typo.body(13)).foregroundStyle(Pal.fg2)
                Text("\(n)").font(Typo.mono(22)).foregroundStyle(Pal.ink).contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .glassRect(20)
        }
        .buttonStyle(PressStyle())
    }

    private func segRow(_ s: Segment, first: Bool) -> some View {
        let selecting: Bool = store.segSelecting
        let picked: Bool = store.segSelected.contains(s.id)
        return VStack(spacing: 0) {
            if !first { Rectangle().fill(Pal.line).frame(height: 0.5) }
            HStack(spacing: 10) {
                Button {
                    if selecting {
                        haptic()
                        withAnimation(.spring(response: 0.25)) { store.toggleSegSelected(s.id) }
                    } else {
                        store.segmentFilter = s
                        store.leadFilter = "all"
                        store.tab = .leads
                    }
                } label: {
                    HStack(spacing: 12) {
                        if selecting {
                            Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                                .iconFont(22)
                                .foregroundStyle(picked ? Pal.ink : Pal.ink.opacity(0.35))
                                .transition(.scale.combined(with: .opacity))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.niche + " · " + s.city).font(Typo.body(15, .semibold)).foregroundStyle(Pal.ink)
                                .lineLimit(2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            Text(segLine(s)).font(Typo.body(13)).foregroundStyle(Pal.fg2).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if !selecting {
                    Button { Task { await store.toggleSegment(s) } } label: {
                        Text(s.on ? "пауза" : "возобновить").font(Typo.body(13, .semibold))
                            .foregroundStyle(s.on ? Pal.ink : Pal.onInk)
                            .padding(.horizontal, 14).frame(minHeight: 34)
                            .background(Capsule().fill(s.on ? Pal.ink.opacity(0.07) : Pal.ink))
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(minHeight: 60)
            .background(Pal.ink.opacity(selecting && picked ? 0.05 : 0))
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button { Task { await store.toggleSegment(s) } } label: {
                Label(s.on ? "поставить на паузу" : "возобновить", systemImage: s.on ? "pause.circle" : "play.circle")
            }
            if !selecting {
                Button { store.startSegSelecting(s.id) } label: { Label("выбрать несколько", systemImage: "checkmark.circle") }
            }
            Button(role: .destructive) {
                singleDelete = s.id
                store.segConfirmDelete = true
            } label: { Label("удалить подборку", systemImage: "trash") }
        }
    }

    private func segLine(_ s: Segment) -> String {
        if let m = s.mismatch, !m.isEmpty { return String(localized: "не подходит под ваш товар") }
        if !s.on { return String(localized: "на паузе, лимит не тратится") }
        if s.exhausted { return String(localized: "выдано \(s.issued) · компании закончились") }
        if s.found == 0 { return String(localized: "идёт сбор") }
        return String(localized: "выдано \(s.issued) · осталось ≈ \(s.left)")
    }
}

struct SignalCard: View {
    @Environment(Store.self) private var store
    let signal: Signal
    let action: () -> Void

    var body: some View {
        let seen = store.seenSignals.contains(signal.id)
        let info = SignalKind.info(signal.type)
        Button { haptic(); action() } label: {
            HStack(spacing: 12) {
                Circle().fill(seen ? Pal.seen : Pal.unseen).frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Pal.ink.opacity(seen ? 0 : 0.15), lineWidth: 4).scaleEffect(1.6))
                VStack(alignment: .leading, spacing: 3) {
                    Text(signal.name + " — " + info.0).font(Typo.body(15, .semibold)).foregroundStyle(Pal.ink).lineLimit(2).multilineTextAlignment(.leading)
                    Text(cardLine).font(Typo.body(13)).foregroundStyle(Pal.fg2).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").iconFont(13, .semibold).foregroundStyle(Pal.ink.opacity(0.4))
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassRect(24)
        }
        .buttonStyle(PressStyle())
    }

    private var cardLine: String {
        var parts: [String] = [capFirst(signal.city), Fmt.when(signal.date)]
        if let p = signal.power { parts.append(String(localized: "шанс ответа \(p)/10")) }
        return joinParts(parts)
    }
}

/// Панель действий с выбранными подборками (вместо таб-бара).
struct SegmentSelectionBar: View {
    @Environment(Store.self) private var store

    var body: some View {
        let sel: Set<Int> = store.segSelected
        let none: Bool = sel.isEmpty
        HStack(spacing: 2) {
            item("pause.circle", String(localized: "пауза"), disabled: none) {
                store.stopSegSelecting()
                Task { await store.setSegments(sel, on: false) }
            }
            item("play.circle", String(localized: "возобновить"), disabled: none) {
                store.stopSegSelecting()
                Task { await store.setSegments(sel, on: true) }
            }
            item("trash", String(localized: "удалить"), disabled: none) {
                store.segConfirmDelete = true
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

    private func item(_ icon: String, _ title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            haptic()
            action()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).iconFont(20).frame(minHeight: 25)
                Text(title).font(Typo.body(13, .semibold)).lineLimit(1)
            }
            .foregroundStyle(Pal.ink.opacity(disabled ? 0.3 : 1))
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(disabled)
    }
}
