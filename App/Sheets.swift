import SwiftUI

struct SheetBox<Content: View>: View {
    let title: String?
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content
    @State private var height: CGFloat = 300

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if let title {
                    Text(title).font(Typo.display(18)).tracking(-0.5).foregroundStyle(Pal.ink).padding(.horizontal, 8)
                }
                if let subtitle {
                    Text(subtitle).font(Typo.body(13)).foregroundStyle(Pal.fg2).padding(.horizontal, 8).padding(.bottom, 6)
                }
                content()
            }
            .padding(.horizontal, 12).padding(.top, 22).padding(.bottom, 12)
            .background(GeometryReader { g in Color.clear.preference(key: SheetHeightKey.self, value: g.size.height) })
        }
        .scrollBounceBehavior(.basedOnSize)
        .onPreferenceChange(SheetHeightKey.self) { h in if h > 0 { height = min(h + 8, 720) } }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .modifier(SheetChrome())
    }
}

struct SheetChrome: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content.presentationCornerRadius(34).presentationBackground(.ultraThinMaterial)
        }
    }
}

private struct SheetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct SheetOption<Trailing: View>: View {
    let icon: String?
    let title: String
    var subtitle: String? = nil
    var on = false
    var dot: Color? = nil
    let action: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        Button(action: { haptic(); action() }) {
            HStack(spacing: 12) {
                if let dot { Circle().fill(dot).frame(width: 12, height: 12).padding(.horizontal, 4) }
                if let icon { Image(systemName: icon).iconFont(18).foregroundStyle(Pal.ink.opacity(0.7)).frame(width: 22) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Typo.body(16)).foregroundStyle(Pal.ink).multilineTextAlignment(.leading)
                    if let subtitle { Text(subtitle).font(Typo.body(13)).foregroundStyle(Pal.fg3).lineLimit(2) }
                }
                Spacer(minLength: 0)
                trailing()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(on ? Pal.ink.opacity(0.06) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

extension SheetOption where Trailing == EmptyView {
    init(icon: String?, title: String, subtitle: String? = nil, on: Bool = false, dot: Color? = nil, action: @escaping () -> Void) {
        self.init(icon: icon, title: title, subtitle: subtitle, on: on, dot: dot, action: action, trailing: { EmptyView() })
    }
}

/// «Написать через»: только каналы, которые реально есть у фирмы. Текст копируется, статус → «связались».
struct WriteSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let lead: Lead
    let message: String

    var body: some View {
        let enc = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        SheetBox(title: String(localized: "написать через"), subtitle: String(localized: "текст первого сообщения скопируется, статус станет «связались»")) {
            if let e = lead.email, !e.isEmpty, let u = mailtoURL(e, body: message) {
                SheetOption(icon: "envelope", title: String(localized: "почта"), subtitle: e, action: { go(u, via: String(localized: "почта")) })
            }
            // WhatsApp — только если фирма сама его указала (lead.wa); на мобильный номер без проверки WhatsApp может не быть — пишем SMS
            if lead.mobilePhone, let p = lead.phone, let u = URL(string: "sms:\(p.filter { $0.isNumber || $0 == "+" })&body=\(enc)") {
                SheetOption(icon: "message", title: "SMS", subtitle: p, action: { go(u, via: "SMS") })
            }
            if let w = lead.wa, !w.isEmpty, let u = externalURL(w) {
                SheetOption(icon: nil, title: String(localized: "WhatsApp компании"), subtitle: shortLink(w), dot: Color(hex: 0x25D366), action: { go(u, via: "WhatsApp") })
            }
            if let t = lead.tg, !t.isEmpty, let u = externalURL(t) {
                SheetOption(icon: nil, title: "Telegram", subtitle: shortLink(t), dot: Color(hex: 0x2AABEE), action: { go(u, via: "Telegram") })
            }
            if let s = lead.site, !s.isEmpty, let u = externalURL(s) {
                SheetOption(icon: "globe", title: String(localized: "форма на сайте"), subtitle: shortLink(s), action: { go(u, via: String(localized: "форма на сайте")) }) {
                    Image(systemName: "arrow.up.right").iconFont(13).foregroundStyle(Pal.ink.opacity(0.4))
                }
            }
            if (lead.email ?? "").isEmpty && (lead.phone ?? "").isEmpty && (lead.site ?? "").isEmpty && (lead.wa ?? "").isEmpty && (lead.tg ?? "").isEmpty {
                Text("у фирмы нет контактов для сообщения").font(Typo.body(14)).foregroundStyle(Pal.fg2).padding(8)
            }
        }
    }

    private func go(_ u: URL, via: String) {
        UIPasteboard.general.string = message
        dismiss()
        openURL(u)
        Task {
            if lead.st == .new { await store.setStatus(lead.id, .written) }
            store.show(String(localized: "текст скопирован, статус «связались» · \(via)"))
        }
    }
}

struct CallSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let lead: Lead

    var body: some View {
        SheetBox(title: String(localized: "позвонить")) {
            if let p = lead.phone, !p.isEmpty {
                Text(p).font(Typo.mono(22)).foregroundStyle(Pal.ink).frame(maxWidth: .infinity).padding(.vertical, 8).textSelection(.enabled)
                SheetOption(icon: "phone", title: String(localized: "обычный звонок"), action: {
                    if let u = URL(string: "tel:" + p.filter { $0.isNumber || $0 == "+" }) { openURL(u) }
                    dismiss()
                    Task { if lead.st == .new { await store.setStatus(lead.id, .written) } }
                })
                if let w = lead.wa, !w.isEmpty, let u = externalURL(w) {
                    SheetOption(icon: nil, title: String(localized: "звонок в WhatsApp"), subtitle: String(localized: "откроет чат, там кнопка звонка"), dot: Color(hex: 0x25D366), action: {
                        openURL(u); dismiss()
                        Task { if lead.st == .new { await store.setStatus(lead.id, .written) } }
                    })
                }
                SheetOption(icon: "doc.on.doc", title: String(localized: "скопировать номер"), action: { UIPasteboard.general.string = p; store.show(String(localized: "скопировано")) })
            } else {
                Text("телефона у фирмы нет — напишите на почту или через сайт").font(Typo.body(15)).foregroundStyle(Pal.fg2).padding(.horizontal, 10).padding(.vertical, 8)
            }
            Text("После звонка поставьте статус — так менеджеры не позвонят второй раз").font(Typo.body(13)).foregroundStyle(Pal.fg3).padding(.horizontal, 10).padding(.top, 6)
        }
    }
}

struct ManagerSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let lead: Lead
    @State private var adding = false

    var body: some View {
        SheetBox(title: String(localized: "кто ведёт")) {
            SheetOption(icon: "person", title: String(localized: "вы"), on: lead.managerId == nil, action: { dismiss(); Task { await store.setManager(lead.id, nil) } }) {
                if lead.managerId == nil { Image(systemName: "checkmark").foregroundStyle(Pal.ink) }
            }
            ForEach(store.managers) { m in
                SheetOption(icon: "person", title: m.name, subtitle: m.email.isEmpty ? nil : m.email, on: lead.managerId == m.id, action: { dismiss(); Task { await store.setManager(lead.id, m) } }) {
                    if lead.managerId == m.id { Image(systemName: "checkmark").foregroundStyle(Pal.ink) }
                }
            }
            if store.managers.isEmpty {
                Text("менеджеров пока нет — их можно добавить в настройках").font(Typo.body(13)).foregroundStyle(Pal.fg2).padding(.horizontal, 10).padding(.top, 4)
            }
        }
    }
}

struct AddManagerSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var busy = false

    var body: some View {
        SheetBox(title: String(localized: "новый менеджер"), subtitle: String(localized: "на почту придёт приглашение со входом")) {
            VStack(spacing: 8) {
                input(String(localized: "имя"), $name)
                input(String(localized: "почта"), $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                Button {
                    guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    busy = true
                    Task {
                        let ok = await store.addManager(name: name.trimmingCharacters(in: .whitespaces), email: email.trimmingCharacters(in: .whitespaces))
                        busy = false
                        if ok { dismiss() }
                    }
                } label: {
                    ZStack { if busy { ProgressView().tint(.white) } else { Text("добавить").font(Typo.body(16, .semibold)) } }
                        .frame(maxWidth: .infinity).frame(minHeight: 50).primaryFill(16)
                }
                .buttonStyle(PressStyle())
            }
            .padding(4)
        }
    }

    private func input(_ p: String, _ t: Binding<String>) -> some View {
        TextField("", text: t, prompt: Text(p).foregroundColor(Pal.fg3))
            .font(Typo.body(16)).foregroundStyle(Pal.ink)
            .padding(.horizontal, 16).frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Pal.surface.opacity(0.78)))
    }
}

/// Сигнал: событие, контакты (если открыты) и готовое сообщение под событие — с бэкенда.
struct SignalSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let signal: Signal
    @State private var detail: SignalDetail?
    @State private var busy = false
    @State private var writeLead: Lead?

    var body: some View {
        let info = SignalKind.info(signal.type)
        SheetBox(title: signal.name, subtitle: joinParts([capFirst(signal.city), Fmt.when(signal.date), signal.niche])) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("СИГНАЛ").font(Typo.body(13, .semibold)).tracking(0.96).foregroundStyle(Pal.ink)
                    Spacer()
                    if let p = signal.power { Text("шанс ответа \(p)/10").font(Typo.body(13, .semibold)).foregroundStyle(Pal.ink) }
                }
                Text(info.0).font(Typo.display(17)).foregroundStyle(Pal.ink).padding(.top, 2)
                Text(signal.text ?? info.1).font(Typo.body(14)).foregroundStyle(Pal.fg2)
                if let d = signal.detail, !d.isEmpty { Text(d).font(Typo.body(13)).foregroundStyle(Pal.fg3).lineLimit(1) }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassRect(22)
            .padding(.horizontal, 4)
            if let m = detail?.message, !m.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("СООБЩЕНИЕ ПОД СОБЫТИЕ").font(Typo.body(13, .semibold)).tracking(0.96).foregroundStyle(Pal.fg2)
                    Text(m).font(Typo.body(14)).foregroundStyle(Pal.ink).lineSpacing(3).textSelection(.enabled)
                    if let own = detail?.messageOwn, !own.isEmpty { Text("перевод: \(own)").font(Typo.body(13)).foregroundStyle(Pal.fg2) }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .glassRect(20).padding(.horizontal, 4).padding(.top, 8)
            } else if detail == nil {
                ProgressView().tint(Pal.ink).frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            Button { Task { await take(thenWrite: true) } } label: {
                ZStack { if busy { ProgressView().tint(.white) } else { Label("написать им", systemImage: "paperplane").font(Typo.body(16, .semibold)) } }
                    .frame(maxWidth: .infinity).frame(minHeight: 52).primaryFill(16)
            }
            .buttonStyle(PressStyle())
            .padding(.top, 10)
            SheetOption(icon: "plus", title: signal.issued ? String(localized: "открыть в компаниях") : String(localized: "добавить в компании"), action: { Task { await take(thenWrite: false) } })
            ForEach(detail?.contacts ?? [], id: \.self) { c in
                SheetOption(icon: icon(c.kind), title: c.value, subtitle: kindName(c.kind), action: {
                    if c.kind == "phone", let u = URL(string: "tel:" + c.value.filter { $0.isNumber || $0 == "+" }) { openURL(u) }
                    else if c.kind == "email" { UIPasteboard.general.string = c.value.replacingOccurrences(of: "mailto:", with: ""); store.show(String(localized: "скопировано")) }
                    else if let u = externalURL(c.value) { openURL(u) }
                })
            }
            if let site = detail?.org?.site, !site.isEmpty, let u = externalURL(site) {
                SheetOption(icon: "globe", title: String(localized: "проверить сайт"), subtitle: shortLink(site), action: { openURL(u) })
            }
        }
        .sheet(item: $writeLead) { lead in
            WriteSheet(lead: lead, message: lead.message ?? detail?.message ?? "")
        }
        .task {
            if store.fixture { return }
            detail = try? await API.get(SignalDetail.self, "/api/cabinet/signals/\(signal.id)/")
        }
    }

    /// подпись контакта: код с сервера (phone, email…) → слово на языке интерфейса
    private func kindName(_ k: String) -> String {
        switch k {
        case "phone": return String(localized: "телефон")
        case "email": return String(localized: "почта")
        case "site": return String(localized: "сайт")
        case "whatsapp": return "WhatsApp"
        case "telegram": return "Telegram"
        default: return k
        }
    }

    private func icon(_ k: String) -> String {
        switch k {
        case "phone": return "phone"
        case "email": return "envelope"
        case "whatsapp", "telegram": return "bubble.left"
        default: return "link"
        }
    }

    private func take(thenWrite: Bool) async {
        busy = true
        let id = await store.takeSignal(signal)
        let target = id ?? signal.orgId
        // фирма уже была в лидах со старым текстом — ставим сообщение под это событие, иначе в карточке и в письме уйдёт старое
        if let target, let m = detail?.message?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty,
           let l = store.lead(target), (l.message ?? "") != m {
            _ = await store.saveMessage(target, m)
        }
        busy = false
        if thenWrite, let target, let lead = store.lead(target) {
            writeLead = lead
            return
        }
        dismiss()
        if let target, store.lead(target) != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                store.tab = .leads
                store.leadFilter = "all"
                store.leadsPath = [.lead(target)]
            }
        }
    }
}

struct CitySheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (String) -> Void
    @State private var city = ""
    @FocusState private var focused: Bool

    var body: some View {
        SheetBox(title: String(localized: "добавить город")) {
            HStack(spacing: 8) {
                TextField("", text: $city, prompt: Text("например: мадрид").foregroundColor(Pal.fg3))
                    .font(Typo.body(16)).foregroundStyle(Pal.ink).focused($focused).submitLabel(.done).onSubmit(add)
                    .padding(.horizontal, 16).frame(minHeight: 54)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Pal.surface.opacity(0.78)))
                Button(action: add) { Text("ок").font(Typo.body(16, .semibold)).padding(.horizontal, 18).frame(minHeight: 54).primaryFill() }
                    .buttonStyle(PressStyle())
            }
            .padding(4)
        }
        .onAppear { focused = true }
    }

    private func add() {
        let v = city.trimmingCharacters(in: .whitespaces).lowercased()
        guard !v.isEmpty else { return }
        onAdd(v)
        dismiss()
    }
}

/// Удаление аккаунта (POST /api/cabinet/account/delete {"confirm":"удалить"}) — для менеджера «выйти из команды»
/// (POST /api/cabinet/account/leave {"confirm":"выйти"}). Слово-подтверждение в поле — на языке интерфейса,
/// на сервер всегда уходит русское. После успеха — текст про Sguardo с сервера, очистка данных и экран входа.
struct DeleteSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var leave = false
    @State private var typed = ""
    @State private var busy = false
    @State private var error: String?
    /// аккаунт удалён / вышли из команды: текст про Sguardo с сервера
    @State private var done: String?
    @State private var started = false
    @FocusState private var focused: Bool

    private var word: String {
        leave ? String(localized: "account.leave.word", defaultValue: "выйти") : String(localized: "account.delete.word", defaultValue: "удалить")
    }
    private var matches: Bool {
        let t = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t == word.lowercased() || t == (leave ? "выйти" : "удалить")
    }

    var body: some View {
        SheetBox(title: nil) {
            if let d = done { doneView(d) } else { askView }
        }
        .interactiveDismissDisabled(busy || done != nil)
        .onAppear {
            guard !started else { return }
            started = true
            leave = store.user?.isManager == true
        }
    }

    private var askView: some View {
        VStack(spacing: 10) {
            Text(leave ? "Выйти из команды?" : "Удалить аккаунт?").font(Typo.display(18)).foregroundStyle(Pal.ink)
                .multilineTextAlignment(.center)
            Text(leave ? "Вы потеряете доступ к кабинету владельца. Компании, которые вы вели, останутся у него." : "Удалим кабинет, подборки, компании, тексты, менеджеров и почтовые ящики — вернуть нельзя. Платежи остаются в бухгалтерии без ваших данных.")
                .font(Typo.body(15)).foregroundStyle(Pal.fg2).multilineTextAlignment(.center).lineSpacing(3).padding(.horizontal, 6)
                .fixedSize(horizontal: false, vertical: true)
            Text("Чтобы подтвердить, напишите «\(word)»").font(Typo.body(14, .semibold)).foregroundStyle(Pal.ink)
                .multilineTextAlignment(.center).padding(.top, 6)
            TextField("напишите «\(word)»", text: $typed)
                .focused($focused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .font(Typo.body(16))
                .padding(.horizontal, 16).frame(minHeight: 50)
                .glassRect(16)
                .accessibilityLabel(Text("слово для подтверждения"))
            if let e = error {
                Text(e).font(Typo.body(14, .semibold)).foregroundStyle(Pal.danger).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { run() } label: {
                Group {
                    if busy { ProgressView() } else { Text(leave ? "выйти из команды" : "удалить навсегда") }
                }
                .font(Typo.body(16, .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(minHeight: 50)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Pal.danger.opacity(matches && !busy ? 1 : 0.35)))
            }
            .buttonStyle(PressStyle())
            .disabled(!matches || busy)
            .padding(.top, 4)
            Button { dismiss() } label: { Text("отмена").font(Typo.body(16, .semibold)).foregroundStyle(Pal.ink).frame(maxWidth: .infinity).frame(minHeight: 50) }
                .disabled(busy)
        }
        .frame(maxWidth: .infinity).padding(.bottom, 8)
    }

    private func doneView(_ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle").iconFont(34, .regular).foregroundStyle(Pal.ink).accessibilityHidden(true)
            Text(leave ? "Вы вышли из команды" : "Аккаунт удалён").font(Typo.display(18)).foregroundStyle(Pal.ink)
            if !text.isEmpty {
                Text(text).font(Typo.body(15)).foregroundStyle(Pal.fg2).multilineTextAlignment(.center).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { finish() } label: {
                Text("понятно").font(Typo.body(16, .semibold)).frame(maxWidth: .infinity).frame(minHeight: 50).primaryFill(16)
            }
            .buttonStyle(PressStyle())
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity).padding(.bottom, 8)
    }

    private func run() {
        guard matches, !busy else { return }
        focused = false
        error = nil
        if store.fixture { done = ""; return }
        if !NetMonitor.shared.online { error = String(localized: "нет интернета"); return }
        busy = true
        let isLeave: Bool = leave
        Task {
            do {
                let (status, obj) = try await Self.post(isLeave ? "/api/cabinet/account/leave/" : "/api/cabinet/account/delete/",
                                                        ["confirm": isLeave ? "выйти" : "удалить"])
                busy = false
                handle(status, obj, wasLeave: isLeave)
            } catch {
                busy = false
                self.error = friendly(error)
            }
        }
    }

    private func handle(_ status: Int, _ obj: [String: Any], wasLeave: Bool) {
        let code: String = obj["code"] as? String ?? ""
        let message: String? = obj["error"] as? String
        if status < 300 && (obj["ok"] as? Bool) != false {
            done = obj["sguardo"] as? String ?? ""
            wipe()
            return
        }
        switch (status, code) {
        case (403, "manager"):
            // менеджер не удаляет аккаунт владельца — предлагаем выйти из команды
            leave = true
            typed = ""
            error = String(localized: "Вы менеджер в чужом кабинете — удалить его нельзя, но можно выйти из команды.")
        case (403, "service_owner"):
            error = String(localized: "аккаунт владелицы сервиса удалить нельзя")
        case (400, "confirm"):
            typed = ""
            error = String(localized: "слово не совпало — напишите его ещё раз")
        case (401, _):
            error = String(localized: "нужно войти заново")
        default:
            error = message ?? (status == 0 ? String(localized: "нет ответа от сервера") : API.errorText(Data(), status: status))
        }
    }

    /// сразу после успеха: сессия и данные этого аккаунта на телефоне больше не нужны
    private func wipe() {
        let mail: String = (store.user?.email ?? "").lowercased()
        let d = UserDefaults.standard
        if !mail.isEmpty {
            for k in ["povod.folders.server:", "povod.folders.imported:", "leadFolders:", "povod.hiddenCampaigns:"] { d.removeObject(forKey: k + mail) }
        }
        store.stopPolling()
        API.clearCookies()
    }

    private func finish() {
        dismiss()
        store.stopPolling()
        store.resetAll()
        withAnimation { store.phase = .login }
    }

    /// POST без исключения на 4xx: нужен код ответа и поле code
    private static func post(_ path: String, _ json: [String: Any]) async throws -> (Int, [String: Any]) {
        var req = URLRequest(url: API.url(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("ru", forHTTPHeaderField: "Accept-Language")
        req.httpBody = try JSONSerialization.data(withJSONObject: json)
        let (data, resp) = try await API.session.data(for: req)
        let status: Int = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let obj: [String: Any] = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return (status, obj)
    }
}
