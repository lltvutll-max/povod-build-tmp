import SwiftUI

struct LeadView: View {
    @Environment(Store.self) private var store
    @Environment(\.openURL) private var openURL
    let leadId: Int
    @State private var msg = ""
    @State private var note = ""
    @State private var loaded = false
    @State private var sheet: LeadSheet?
    @State private var confirmDelete = false
    @FocusState private var focus: Field?
    enum Field { case msg, note }
    enum LeadSheet: String, Identifiable { case write, call, manager; var id: String { rawValue } }

    var body: some View {
        Group {
            if let l = store.lead(leadId) {
                content(l)
            } else {
                VStack {
                    HStack { CircleButton(system: "chevron.left", iconSize: 18) { store.pop() }; Spacer() }.padding(16)
                    Text("компания не найдена").font(Typo.body(15)).foregroundStyle(Pal.fg2)
                    Spacer()
                }
            }
        }
        .metalBackground(.none)
        .onAppear {
            guard !loaded, let l = store.lead(leadId) else { return }
            msg = l.message ?? ""
            note = l.note ?? ""
            loaded = true
            if store.user?.isManager != true && store.managers.isEmpty { Task { await store.loadSettings() } }
        }
        .onDisappear { saveEdits() }
        .sheet(item: $sheet) { s in
            if let l = store.lead(leadId) {
                switch s {
                case .write: WriteSheet(lead: l, message: msg)
                case .call: CallSheet(lead: l)
                case .manager: ManagerSheet(lead: l)
                }
            }
        }
    }

    private func saveEdits() {
        let m = msg, n = note, id = leadId
        Task {
            if loaded { _ = await store.saveMessage(id, m) }
            if loaded { await store.saveNote(id, n) }
        }
    }

    private func statusControl(_ lead: Lead) -> some View {
        let items = LeadStatus.allCases.map { ($0, $0.title) }
        let selection = Binding<LeadStatus>(get: { lead.st }, set: { status in
            Task<Void, Never> { await store.setStatus(lead.id, status) }
        })
        return GlassSegment(items: items, selection: selection, fontSize: 13)
    }

    private func content(_ l: Lead) -> some View {
        let code = Reason.code(l)
        return VStack(spacing: 0) {
            HStack {
                CircleButton(system: "chevron.left", iconSize: 18) { saveEdits(); store.pop() }
                Spacer()
                if let s = l.site, !s.isEmpty, let u = webURL(s) {
                    PillButton(action: { openURL(u) }) { Image(systemName: "globe").iconFont(15); Text("сайт") }
                } else {
                    Text("сайта нет").font(Typo.body(14, .semibold)).foregroundStyle(Pal.fg2).padding(.horizontal, 16).frame(minHeight: 40).glassCapsule()
                }
            }
            .padding(.horizontal, 16).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HintCard(key: Guide.hintLead, icon: "paperplane",
                             title: String(localized: "как связаться"),
                             text: String(localized: "Нажмите «написать» и выберите, куда: текст скопируется, а почта или мессенджер откроются сами — останется вставить и отправить. Статус сменится на «связались». Если компания за рубежом, сообщение уже на её языке, а под ним — перевод для вас."))
                        .padding(.top, 12)
                    Text(l.name).font(Typo.display(24)).tracking(-0.8).lineSpacing(2).foregroundStyle(Pal.ink).padding(.horizontal, 4).padding(.top, 18)
                    Text(subtitle(l)).font(Typo.body(14)).foregroundStyle(Pal.fg2).lineSpacing(3).padding(.horizontal, 4).padding(.top, 6)
                    HStack(spacing: 8) {
                        let canWrite = l.canWrite
                        let canCall = l.canCall
                        Button { sheet = .write } label: {
                            Label("написать", systemImage: "paperplane").font(Typo.body(16, .semibold)).frame(maxWidth: .infinity).frame(minHeight: 52)
                                .modifier(ActionFill(on: canWrite, primary: true))
                        }
                        .buttonStyle(PressStyle())
                        .disabled(!canWrite)
                        .accessibilityHint(canWrite ? Text(verbatim: "") : Text("нет почты и мессенджеров"))
                        Button { sheet = .call } label: {
                            Label("позвонить", systemImage: "phone").font(Typo.body(16, .semibold)).frame(maxWidth: .infinity).frame(minHeight: 52)
                                .modifier(ActionFill(on: canCall, primary: false))
                        }
                        .buttonStyle(PressStyle())
                        .disabled(!canCall)
                        .accessibilityHint(canCall ? Text(verbatim: "") : Text("нет телефона"))
                    }
                    .padding(.top, 16)
                    if let why = disabledReason(l) {
                        Text(why).font(Typo.body(13)).foregroundStyle(Pal.fg2).padding(.horizontal, 4).padding(.top, 6)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("ПОВОД").font(Typo.body(13, .semibold)).tracking(0.96).foregroundStyle(Pal.ink)
                            Spacer()
                            if l.power > 0 {
                                Text("шанс ответа").font(Typo.body(13)).foregroundStyle(Pal.fg2)
                                PowerBar(p: l.power)
                                Text("\(l.power)/10").font(Typo.mono(13)).foregroundStyle(Pal.ink).accessibilityHidden(true)
                            }
                        }
                        Text(Reason.title[code] ?? code).font(Typo.display(17)).tracking(-0.5).lineSpacing(3).foregroundStyle(Pal.ink).padding(.top, 8)
                        if let w = l.whatsWrong, !w.isEmpty, w != Reason.title[code] {
                            Text(w).font(Typo.body(14)).foregroundStyle(Pal.fg2).lineSpacing(3).padding(.top, 6)
                        }
                        if let d = l.date {
                            Text("выдан \(Fmt.when(d))").font(Typo.body(13)).foregroundStyle(Pal.fg3).padding(.top, 8)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassRect(24)
                    .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("ПЕРВОЕ СООБЩЕНИЕ").font(Typo.body(13, .semibold)).tracking(0.96).foregroundStyle(Pal.fg2)
                            Spacer()
                            Text("\(msg.count) симв.").font(Typo.body(13)).foregroundStyle(Pal.fg3)
                        }
                        TextField("", text: $msg, prompt: Text("сообщение ещё готовится").foregroundColor(Pal.fg3), axis: .vertical)
                            .lineLimit(4...16)
                            .font(Typo.body(15)).lineSpacing(4).foregroundStyle(Pal.ink)
                            .focused($focus, equals: .msg)
                        if let own = l.messageOwn, !own.isEmpty {
                            Text("перевод: \(own)").font(Typo.body(13)).foregroundStyle(Pal.fg2).lineSpacing(3)
                        }
                        HStack(spacing: 8) {
                            PillButton(action: {
                                UIPasteboard.general.string = msg
                                store.show(String(localized: "сообщение скопировано"))
                            }) { Image(systemName: "doc.on.doc").iconFont(14); Text("копировать") }
                            .frame(maxWidth: .infinity)
                            if msg != (l.message ?? "") {
                                PillButton(action: { msg = l.message ?? "" }) { Image(systemName: "arrow.counterclockwise").iconFont(14); Text("как было") }
                            }
                        }
                    }
                    .padding(16)
                    .glassRect(24)
                    .padding(.top, 10)

                    Cap(String(localized: "статус"))
                    statusControl(l)

                    Cap(String(localized: "папка"))
                    folderRow(l)

                    Cap(String(localized: "контакты"))
                    VStack(spacing: 0) {
                        let rows = contactRows(l)
                        if rows.isEmpty { GroupRow(first: true) { Text("контактов нет").foregroundStyle(Pal.fg2) } }
                        ForEach(rows.indices, id: \.self) { i in
                            let r = rows[i]
                            Button { r.action() } label: {
                                GroupRow(first: i == 0) {
                                    Text(r.label).foregroundStyle(Pal.fg2).frame(width: 84, alignment: .leading)
                                    Text(r.value).font(r.mono ? Typo.mono(14, .medium) : Typo.body(15)).foregroundStyle(Pal.ink).lineLimit(1)
                                    Spacer()
                                    Image(systemName: r.icon).iconFont(14).foregroundStyle(Pal.ink.opacity(0.4))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(RowPressStyle())
                        }
                    }
                    .glassRect(24)

                    Cap(String(localized: "кто ведёт"))
                    VStack(spacing: 0) {
                        if store.user?.isManager != true {
                            Button { sheet = .manager } label: {
                                GroupRow(first: true) {
                                    Text("менеджер")
                                    Spacer()
                                    Text(l.manager ?? String(localized: "вы")).font(Typo.body(16, .semibold))
                                    Image(systemName: "chevron.right").iconFont(13, .semibold).foregroundStyle(Pal.ink.opacity(0.4))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(RowPressStyle())
                        }
                        GroupRow(first: store.user?.isManager == true) {
                            Text("заметка").frame(width: 84, alignment: .leading)
                            TextField("", text: $note, prompt: Text("например: позвонить после 12").foregroundColor(Pal.fg3), axis: .vertical)
                                .lineLimit(1...5).font(Typo.body(15)).foregroundStyle(Pal.ink)
                                .focused($focus, equals: .note)
                                .padding(.vertical, 12)
                        }
                    }
                    .glassRect(24)

                    if store.user?.isManager != true {
                        Button { confirmDelete = true } label: {
                            HStack(spacing: 8) { Image(systemName: "trash"); Text("удалить из кабинета") }
                                .font(Typo.body(15, .semibold)).foregroundStyle(Pal.danger)
                                .frame(maxWidth: .infinity).frame(minHeight: 48)
                        }
                        .buttonStyle(PressStyle())
                        .padding(.top, 18)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .alert("Удалить «\(l.name)» из кабинета?", isPresented: $confirmDelete) {
                Button("удалить", role: .destructive) { store.pop(); store.deleteLead(l.id) }
                Button("отмена", role: .cancel) {}
            } message: { Text("Компания пропадёт из списков. Ещё 9 секунд можно будет нажать «отменить».") }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("готово") { saveEdits(); focus = nil }.font(Typo.body(16, .semibold))
            }
        }
    }

    /// почему кнопка серая
    private func disabledReason(_ l: Lead) -> String? {
        switch (l.canWrite, l.canCall) {
        case (false, false): return String(localized: "написать и позвонить нельзя: у компании нет ни почты, ни мессенджеров, ни телефона")
        case (false, true): return String(localized: "написать нельзя: нет почты и мессенджеров — можно позвонить")
        case (true, false): return String(localized: "позвонить нельзя: телефона нет")
        default: return nil
        }
    }

    private func subtitle(_ l: Lead) -> String {
        var parts: [String] = [capFirst(l.city), l.niche]
        if let r = l.rating, r > 0 { parts.append(Fmt.rating(r) + " ★") }
        if let n = l.reviews, n > 0 { parts.append(String(localized: "\(n) отзывов")) }
        return joinParts(parts)
    }

    private struct ContactRow {
        let label: String
        let value: String
        let icon: String
        let mono: Bool
        let action: () -> Void
    }

    private func contactRows(_ l: Lead) -> [ContactRow] {
        var out: [ContactRow] = []
        if let p = l.phone, !p.isEmpty { out.append(ContactRow(label: String(localized: "телефон"), value: p, icon: "phone", mono: true, action: { sheet = .call })) }
        if let e = l.email, !e.isEmpty {
            out.append(ContactRow(label: String(localized: "почта"), value: e, icon: "doc.on.doc", mono: false, action: {
                UIPasteboard.general.string = e
                store.show(String(localized: "скопировано"))
            }))
        }
        if let w = l.wa, !w.isEmpty, let u = externalURL(w) { out.append(ContactRow(label: "whatsapp", value: shortLink(w), icon: "arrow.up.right", mono: false, action: { openURL(u) })) }
        if let t = l.tg, !t.isEmpty, let u = externalURL(t) { out.append(ContactRow(label: "telegram", value: shortLink(t), icon: "arrow.up.right", mono: false, action: { openURL(u) })) }
        if let s = l.site, !s.isEmpty, let u = externalURL(s) { out.append(ContactRow(label: String(localized: "сайт"), value: shortLink(s), icon: "arrow.up.right", mono: false, action: { openURL(u) })) }
        return out
    }
}

/// Только http/https с хостом — адрес сайта из данных компании (11.11.2026, проверка безопасности).
func webURL(_ raw: String) -> URL? {
    let s: String = raw.trimmingCharacters(in: .whitespaces)
    let full: String = (s.hasPrefix("http://") || s.hasPrefix("https://")) ? s : "https://" + s
    guard let u = URL(string: full), let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https", u.host != nil else { return nil }
    return u
}

/// mailto: только для простого адреса (одна @, без ? & , % пробелов), тело кодируется через URLComponents.
func mailtoURL(_ email: String, body: String) -> URL? {
    let e: String = email.trimmingCharacters(in: .whitespaces)
    guard e.filter({ $0 == "@" }).count == 1, e.rangeOfCharacter(from: CharacterSet(charactersIn: "?&,%/:;<>\"' \t\n")) == nil else { return nil }
    var c = URLComponents()
    c.scheme = "mailto"
    c.path = e
    c.queryItems = [URLQueryItem(name: "body", value: body)]
    return c.url
}

func externalURL(_ raw: String) -> URL? {
    let s = raw.trimmingCharacters(in: .whitespaces)
    if s.hasPrefix("http://") || s.hasPrefix("https://") || s.hasPrefix("tg://") || s.hasPrefix("mailto:") || s.hasPrefix("tel:") { return URL(string: s) }
    return URL(string: "https://" + s)
}

func shortLink(_ s: String) -> String {
    var t = s
    for p in ["https://", "http://", "www."] where t.hasPrefix(p) { t.removeFirst(p.count) }
    if t.hasSuffix("/") { t.removeLast() }
    return t
}


extension LeadView {
    @ViewBuilder func folderRow(_ l: Lead) -> some View {
        let views = store.folders.views(store.leads)
        let cur = store.folders.folderId(l)
        Menu {
            ForEach(views) { v in
                Button {
                    if v.id != cur { store.moveLeads([l], to: v) }
                } label: { Label(v.name, systemImage: v.id == cur ? "checkmark" : (v.custom ? "folder.fill" : "folder")) }
            }
            if store.folders.manualFolderId(l) != nil {
                Divider()
                Button { store.removeLeadFromFolder(l) } label: { Label("убрать из папки", systemImage: "folder.badge.minus") }
            }
        } label: {
            GroupRow(first: true) {
                Image(systemName: cur.hasPrefix("f:") ? "folder.fill" : "folder").iconFont(16).frame(width: 24)
                Text(views.first { $0.id == cur }?.name ?? "\(l.niche) · \(l.city)").lineLimit(1)
                Spacer()
                Text("перенести").font(Typo.body(13, .semibold)).foregroundStyle(Pal.fg2)
                Image(systemName: "chevron.up.chevron.down").iconFont(11, .semibold).foregroundStyle(Pal.fg3)
            }
            .contentShape(Rectangle())
        }
        .glassRect(24)
        .task {
            // карточку могли открыть раньше списка компаний — папки тоже нужны здесь
            store.folders.load(account: store.user?.email ?? "")
            await store.folders.refresh(fixture: store.fixture)
        }
    }
}

/// Кнопки «написать»/«позвонить»: серые и неактивные, если нужных контактов нет.
struct ActionFill: ViewModifier {
    let on: Bool
    let primary: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if !on {
            content.foregroundStyle(Pal.ink.opacity(0.35))
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Pal.ink.opacity(0.06)))
        } else if primary {
            content.primaryFill()
        } else {
            content.foregroundStyle(Pal.ink).contentShape(Rectangle())
                .glass(.light, in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
        }
    }
}

extension Lead {
    /// мобильный ли номер: для России — только +7 9xx (на городской WhatsApp не придёт); другие страны — не знаем, считаем да
    var mobilePhone: Bool {
        let d = (phone ?? "").filter(\.isNumber)
        guard d.count >= 7 else { return false }
        if d.count == 11 && (d.hasPrefix("7") || d.hasPrefix("8")) { return d.dropFirst().hasPrefix("9") }
        return true
    }
    var canCall: Bool { (phone ?? "").filter(\.isNumber).count >= 7 }
    /// свой сайт с формой (не соцсеть и не карточка на картах)
    var ownSite: Bool {
        guard let s = site?.lowercased(), !s.isEmpty else { return false }
        for h in SOCIAL_HOSTS where s.contains(h) { return false }
        return true
    }
    var canWrite: Bool {
        if !(email ?? "").isEmpty || !(tg ?? "").isEmpty || !(wa ?? "").isEmpty { return true }
        return mobilePhone || ownSite
    }
}

private let SOCIAL_HOSTS = ["vk.com", "instagram.com", "t.me", "facebook.com", "ok.ru", "2gis", "yandex.ru/maps", "google.com/maps"]
