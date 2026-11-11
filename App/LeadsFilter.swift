import SwiftUI

// Фильтры списка компаний одной кнопкой «фильтр (N)» (11.11.2026, UX-разборы): статус, повод, сайт.
// Поиск и папка остаются над списком. Плюс выбор папки для одной компании из свайпа «ещё».

struct LeadsFilterSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var status: String
    @Binding var reason: String
    @Binding var site: String

    private var reasons: [String] { Array(Set(store.leads.map { Reason.code($0) })).sorted() }

    private func statusCount(_ code: String) -> Int {
        code == "all" ? store.leads.count : store.leads.filter { $0.status == code }.count
    }

    private func reasonCount(_ code: String) -> Int {
        store.leads.filter { Reason.code($0) == code }.count
    }

    private var siteItems: [(String, String)] {
        [("all", String(localized: "неважно")), ("yes", String(localized: "есть сайт")), ("no", String(localized: "нет сайта"))]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Cap(String(localized: "статус"))
                    group {
                        ForEach(LeadsView.statusTabs.indices, id: \.self) { (i: Int) in
                            let t: (String, String) = LeadsView.statusTabs[i]
                            row(title: t.1, count: statusCount(t.0), on: status == t.0, first: i == 0) { status = t.0 }
                        }
                    }
                    Cap(String(localized: "повод"))
                    group {
                        row(title: String(localized: "любой повод"), count: store.leads.count, on: reason == "all", first: true) { reason = "all" }
                        ForEach(reasons, id: \.self) { (r: String) in
                            row(title: Reason.title[r] ?? (Reason.short[r] ?? r), count: reasonCount(r), on: reason == r, first: false) { reason = r }
                        }
                    }
                    Cap(String(localized: "сайт"))
                    group {
                        ForEach(siteItems.indices, id: \.self) { (i: Int) in
                            let it: (String, String) = siteItems[i]
                            row(title: it.1, count: nil, on: site == it.0, first: i == 0) { site = it.0 }
                        }
                    }
                    Text("Поиск и папка — над списком, они работают вместе с фильтром.")
                        .font(Typo.body(13)).foregroundStyle(Pal.fg2).padding(.horizontal, 4).padding(.top, 12)
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .background(MetalBackground(star: .none).ignoresSafeArea())
            .navigationTitle("фильтр")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("сбросить") {
                        haptic()
                        status = "all"; reason = "all"; site = "all"
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("готово") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func group<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) { content() }.glassRect(22)
    }

    private func row(title: String, count: Int?, on: Bool, first: Bool, action: @escaping () -> Void) -> some View {
        Button {
            haptic()
            withAnimation(.spring(response: 0.3)) { action() }
        } label: {
            GroupRow(first: first) {
                Text(title).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let count { Text("\(count)").font(Typo.mono(13, .medium)).foregroundStyle(Pal.fg2) }
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .iconFont(20)
                    .foregroundStyle(on ? Pal.ink : Pal.ink.opacity(0.3))
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityAddTraits(on ? AccessibilityTraits([.isButton, .isSelected]) : AccessibilityTraits.isButton)
    }
}

/// «Ещё → перенести в папку» для одной компании.
struct LeadFolderPicker: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let lead: Lead

    var body: some View {
        let views: [FolderView] = store.folders.views(store.leads)
        let cur: String = store.folders.folderId(lead)
        SheetBox(title: String(localized: "в какую папку"), subtitle: lead.name) {
            ForEach(views) { (v: FolderView) in
                SheetOption(icon: v.custom ? "folder.fill" : "folder", title: v.name,
                            subtitle: v.custom ? String(localized: "своя папка · \(v.count)") : String(localized: "подборка · \(v.count)"),
                            on: v.id == cur, action: { move(v) })
            }
            Text("Свою папку можно создать в «настроить папки» — в меню папок над списком.")
                .font(Typo.body(13)).foregroundStyle(Pal.fg2).padding(8)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func move(_ v: FolderView) {
        dismiss()
        if v.id != store.folders.folderId(lead) { store.moveLeads([lead], to: v) }
    }
}
