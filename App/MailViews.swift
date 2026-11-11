import SwiftUI
import NaturalLanguage

// Почта в приложении (11.11.2026) — то же, что раздел «почта» веб-кабинета (MailPane.tsx):
// письма (входящие / ответы на рассылки / отправленные), переписка с ответом, рассылки со статистикой
// и запуском/паузой, ящики. API: /api/cabinet/mail/* (src/api/routes/mail.ts).

struct MailBox: Decodable, Identifiable, Hashable {
    let id: Int
    let address: String
    let name: String?
    let dailyLimit: Int?
    let sentToday: Int?
    let unread: Int?
    let syncOk: Bool?
    let syncError: String?
    private enum K: String, CodingKey { case id, address, name, daily_limit, sent_today, unread, sync_ok, sync_error }
    init(id: Int, address: String, name: String?, dailyLimit: Int?, sentToday: Int?, unread: Int?, syncOk: Bool?, syncError: String?) {
        self.id = id; self.address = address; self.name = name; self.dailyLimit = dailyLimit; self.sentToday = sentToday
        self.unread = unread; self.syncOk = syncOk; self.syncError = syncError
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = c.flexInt(.id) ?? 0; address = c.str(.address) ?? ""; name = c.str(.name)
        dailyLimit = c.flexInt(.daily_limit); sentToday = c.flexInt(.sent_today); unread = c.flexInt(.unread)
        syncOk = c.bool(.sync_ok); syncError = c.str(.sync_error)
    }
}

struct MailMsg: Decodable, Identifiable, Hashable {
    let id: Int
    let mailboxId: Int?
    let fromAddr: String
    let fromName: String?
    let to: String?
    let subject: String
    let snippet: String
    let date: String?
    var seen: Bool
    var flagged: Bool = false
    let hasAtt: Bool
    let isReply: Bool
    private enum K: String, CodingKey { case id, mailbox_id, from_addr, from_name, to_addrs, subject, snippet, date, seen, flagged, has_att, is_reply }
    private struct Addr: Decodable { let address: String?; let name: String? }
    init(id: Int, mailboxId: Int?, fromAddr: String, fromName: String?, to: String?, subject: String, snippet: String, date: String?, seen: Bool, hasAtt: Bool, isReply: Bool) {
        self.id = id; self.mailboxId = mailboxId; self.fromAddr = fromAddr; self.fromName = fromName; self.to = to
        self.subject = subject; self.snippet = snippet; self.date = date; self.seen = seen; self.hasAtt = hasAtt; self.isReply = isReply
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = c.flexInt(.id) ?? 0; mailboxId = c.flexInt(.mailbox_id)
        fromAddr = c.str(.from_addr) ?? ""; fromName = c.str(.from_name)
        let addrs = (try? c.decodeIfPresent([Addr].self, forKey: .to_addrs)) ?? nil
        to = addrs?.first.map { ($0.name?.isEmpty == false ? $0.name : $0.address) ?? "" }
        subject = c.str(.subject) ?? ""; snippet = c.str(.snippet) ?? ""; date = c.str(.date)
        seen = c.bool(.seen) ?? true; flagged = c.bool(.flagged) ?? false; hasAtt = c.bool(.has_att) ?? false; isReply = c.bool(.is_reply) ?? false
    }
    var who: String { (fromName?.isEmpty == false ? fromName : nil) ?? fromAddr }
}

struct ThreadMsg: Decodable, Identifiable, Hashable {
    let id: Int
    let mailboxId: Int?
    let folder: String?
    let messageId: String?
    let fromAddr: String
    let fromName: String?
    let toAddr: String?
    let subject: String
    let body: String
    let date: String?
    private enum K: String, CodingKey { case id, mailbox_id, folder, message_id, from_addr, from_name, to_addrs, subject, body_text, date }
    private struct Addr: Decodable { let address: String? }
    init(id: Int, mailboxId: Int?, folder: String?, messageId: String?, fromAddr: String, fromName: String?, toAddr: String?, subject: String, body: String, date: String?) {
        self.id = id; self.mailboxId = mailboxId; self.folder = folder; self.messageId = messageId; self.fromAddr = fromAddr
        self.fromName = fromName; self.toAddr = toAddr; self.subject = subject; self.body = body; self.date = date
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = c.flexInt(.id) ?? 0; mailboxId = c.flexInt(.mailbox_id); folder = c.str(.folder); messageId = c.str(.message_id)
        fromAddr = c.str(.from_addr) ?? ""; fromName = c.str(.from_name)
        toAddr = ((try? c.decodeIfPresent([Addr].self, forKey: .to_addrs)) ?? nil)?.first?.address
        subject = c.str(.subject) ?? ""; body = c.str(.body_text) ?? ""; date = c.str(.date)
    }
    var mine: Bool { folder == "sent" }
}

struct Campaign: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let status: String
    let total: Int
    let sent: Int
    let replied: Int
    let errors: Int
    let today: Int
    let dailyCap: Int?
    let listName: String?
    /// настройки (GET /campaigns отдаёт их; менять — POST /campaigns/:id/edit, CampaignEditSheet)
    var steps: [CampaignStep] = []
    var mailboxIds: [Int] = []
    var windowFrom: Int? = nil
    var windowTo: Int? = nil
    var weekdaysOnly: Bool? = nil
    var reached: Int? = nil
    /// сколько раз ушло каждое письмо цепочки: [N1, N2, …] (письма без отправок в конце не приходят)
    var stepsSent: [Int] = []
    private enum K: String, CodingKey { case id, name, status, total, sent, replied, errors, today, daily_cap, list_name, steps, mailbox_ids, window_from, window_to, weekdays_only, reached, steps_sent }
    init(id: Int, name: String, status: String, total: Int, sent: Int, replied: Int, errors: Int, today: Int, dailyCap: Int?, listName: String?,
         steps: [CampaignStep] = [], mailboxIds: [Int] = [], windowFrom: Int? = nil, windowTo: Int? = nil, weekdaysOnly: Bool? = nil, stepsSent: [Int] = []) {
        self.id = id; self.name = name; self.status = status; self.total = total; self.sent = sent; self.replied = replied
        self.errors = errors; self.today = today; self.dailyCap = dailyCap; self.listName = listName
        self.steps = steps; self.mailboxIds = mailboxIds; self.windowFrom = windowFrom; self.windowTo = windowTo; self.weekdaysOnly = weekdaysOnly
        self.stepsSent = stepsSent
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = c.flexInt(.id) ?? 0; name = c.str(.name) ?? String(localized: "рассылка"); status = c.str(.status) ?? ""
        total = c.flexInt(.total) ?? 0; sent = c.flexInt(.sent) ?? 0; replied = c.flexInt(.replied) ?? 0
        errors = c.flexInt(.errors) ?? 0; today = c.flexInt(.today) ?? 0; dailyCap = c.flexInt(.daily_cap); listName = c.str(.list_name)
        steps = ((try? c.decodeIfPresent([CampaignStep].self, forKey: .steps)) ?? nil) ?? []
        if let ints = (try? c.decodeIfPresent([Int].self, forKey: .mailbox_ids)) ?? nil {
            mailboxIds = ints
        } else if let strs = (try? c.decodeIfPresent([String].self, forKey: .mailbox_ids)) ?? nil {
            mailboxIds = strs.compactMap { Int($0) }
        }
        windowFrom = c.flexInt(.window_from); windowTo = c.flexInt(.window_to); weekdaysOnly = c.bool(.weekdays_only)
        reached = c.flexInt(.reached)
        if let ints = (try? c.decodeIfPresent([Int].self, forKey: .steps_sent)) ?? nil {
            stepsSent = ints
        } else if let strs = (try? c.decodeIfPresent([String].self, forKey: .steps_sent)) ?? nil {
            stepsSent = strs.compactMap { Int($0) }
        }
    }
    /// сколько раз ушло письмо i цепочки (с нуля)
    func sentCount(_ i: Int) -> Int { stepsSent.indices.contains(i) ? stepsSent[i] : 0 }
    var running: Bool { status == "running" || status == "active" }
    var finished: Bool { status == "done" || status == "finished" }
    var statusTitle: String {
        switch status {
        case "running", "active": return String(localized: "идёт")
        case "paused": return String(localized: "на паузе")
        case "done", "finished": return String(localized: "завершена")
        case "draft": return String(localized: "черновик")
        default: return status
        }
    }
    /// «10:00–19:00»
    var windowText: String {
        let f: Int = windowFrom ?? 10
        let t: Int = windowTo ?? 19
        return String(format: "%02d:00–%02d:00", f, t)
    }
}

/// Письмо рассылки: первое — тема и текст, следующие — текст и пауза в днях.
struct CampaignStep: Decodable, Hashable {
    let subject: String
    let body: String
    let delayDays: Int
    private enum K: String, CodingKey { case subject, body, delay_days }
    init(subject: String, body: String, delayDays: Int) { self.subject = subject; self.body = body; self.delayDays = delayDays }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        subject = c.str(.subject) ?? ""; body = c.str(.body) ?? ""; delayDays = c.flexInt(.delay_days) ?? 0
    }
}

private struct BoxesResp: Decodable { let rows: [MailBox] }
private struct ListResp: Decodable { let rows: [MailMsg]; let counts: Counts?; struct Counts: Decodable { let unread: Int?; let replies: Int? } }
private struct ThreadResp: Decodable { let rows: [ThreadMsg] }
private struct CampResp: Decodable { let rows: [Campaign] }

enum MailDate {
    private static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    private static let isoPlain = ISO8601DateFormatter()
    static func parse(_ s: String?) -> Date? { guard let s else { return nil }; return iso.date(from: s) ?? isoPlain.date(from: s) }
    /// даты — в формате текущего языка (сегодня — время, иначе «11 нояб.» / «Nov 11»)
    static func short(_ s: String?) -> String {
        guard let d = parse(s) else { return "" }
        if Calendar.current.isDateInToday(d) { return d.formatted(date: .omitted, time: .shortened) }
        return d.formatted(.dateTime.day().month(.abbreviated))
    }
    static func long(_ s: String?) -> String {
        guard let d = parse(s) else { return "" }
        return d.formatted(.dateTime.day().month(.wide).hour().minute())
    }
}

/// перевод письма: текст и язык оригинала (ISO); хранится в памяти и на диске по id письма + языку
struct MailTranslation: Codable, Hashable {
    let text: String
    let from: String
}

private struct TranslateResp: Decodable { let text: String; let from: String? }

/// Данные почты: живут в отдельном наблюдаемом объекте (в Store — не пересоздаются при переключении вкладок).
/// Ящики, списки писем по папкам, рассылки, переписки и переводы — с копией на телефоне (DiskCache): сразу на экран, свежее в фоне.
@MainActor
@Observable
final class MailStore {
    var boxes: [MailBox] = []
    var rows: [MailMsg] = []
    var unread = 0
    var replies = 0
    var campaigns: [Campaign] = []
    var blocked: String?
    var loading = false
    /// для текущей папки есть что показать (копия или ответ сервера); false — скелетоны
    var listReady = false
    var campaignsReady = false
    var boxesReady = false
    /// фоновое обновление не удалось (данные на экране — сохранённая копия)
    var loadError: String?
    /// какой список сейчас в rows: папка.ящик[?поиск]
    @ObservationIgnored private var listKey = ""
    @ObservationIgnored private var lists: [String: ListResp] = [:]
    private let gate = LoadGate()
    /// чья копия поднята с диска
    @ObservationIgnored private var restoredFor: String?
    @ObservationIgnored private var threads: [Int: [ThreadMsg]] = [:]
    @ObservationIgnored private var translations: [String: MailTranslation] = [:]
    @ObservationIgnored private var translating: [String: Task<MailTranslation, Error>] = [:]

    /// Прежние версии прятали «удалённые» рассылки на телефоне (UserDefaults povod.hiddenCampaigns:<почта>).
    /// Теперь сервер удаляет по-настоящему (POST /campaigns/:id/delete): старый ключ читаем, но ничего не прячем —
    /// такие рассылки стоят на паузе и снова видны в списке, их можно удалить уже на сервере.
    func loadHidden(account: String) {
        _ = UserDefaults.standard.array(forKey: "povod.hiddenCampaigns:" + account.lowercased())
    }

    /// выход / смена аккаунта: всё из памяти (диск стирает DiskCache.clearAll)
    func reset() {
        gate.reset()
        for t in translating.values { t.cancel() }
        translating = [:]
        boxes = []; rows = []; unread = 0; replies = 0; campaigns = []; blocked = nil; loading = false
        listReady = false; campaignsReady = false; boxesReady = false; loadError = nil
        listKey = ""; lists = [:]; restoredFor = nil; threads = [:]; translations = [:]
    }

    /// Поднять копию с телефона (один раз на аккаунт): ящики и рассылки — сразу на экран.
    func restore() {
        guard let acc = DiskCache.account, restoredFor != acc else { return }
        restoredFor = acc
        if boxes.isEmpty, let d = DiskCache.read("mail.boxes"), let r = try? API.decode(BoxesResp.self, d) {
            boxes = r.rows; boxesReady = true
        }
        if campaigns.isEmpty, let d = DiskCache.read("mail.campaigns"), let r = try? API.decode(CampResp.self, d) {
            campaigns = r.rows; campaignsReady = true
        }
    }

    /// Всё для экрана почты: при открытии (force: false — свежее минуты не трогаем) и «потянуть вниз».
    func refresh(folder: String, box: Int?, q: String, fixture: Bool, force: Bool) async {
        if fixture { await loadBoxes(fixture: true); return }
        restore()
        showList(folder: folder, box: box, q: q)
        async let b: Void = loadBoxes(fixture: false, force: force)
        async let l: Void = loadList(folder: folder, box: box, q: q, fixture: false, force: force)
        async let c: Void = loadCampaigns(fixture: false, force: force)
        _ = await (b, l, c)
    }

    func loadBoxes(fixture: Bool, force: Bool = true) async {
        if fixture { Self.fill(self); return }
        await gate.run("boxes", force: force) { [self] in
            let acc: String? = DiskCache.account
            do {
                let d: Data = try await API.send("GET", "/api/cabinet/mail/boxes/")
                let r: BoxesResp = try API.decode(BoxesResp.self, d)
                guard acc == DiskCache.account else { return false }
                if boxes != r.rows { boxes = r.rows }
                blocked = nil
                boxesReady = true
                DiskCache.write(d, "mail.boxes")
                return true
            } catch let e as APIError where e.status == 403 {
                guard acc == DiskCache.account else { return false }
                blocked = e.message
                boxesReady = true
                return true
            } catch {
                guard acc == DiskCache.account else { return false }
                boxesReady = true
                if !isCancellation(error) { loadError = friendly(error) }
                return false
            }
        }
    }

    private static func keyFor(folder: String, box: Int?, q: String) -> String {
        let base: String = "\(folder).\(box ?? 0)"
        return q.isEmpty ? base : base + "?" + q
    }

    /// Показать список папки сразу — из памяти или с телефона, без сети. Нет копии — скелетоны до ответа сервера.
    func showList(folder: String, box: Int?, q: String) {
        let key: String = Self.keyFor(folder: folder, box: box, q: q)
        guard key != listKey else { return }
        listKey = key
        if let r = lists[key] ?? diskList(key, q: q) {
            applyList(r)
            listReady = true
        } else if q.isEmpty {
            // другая папка без копии: старые письма не показываем, чтобы не путать
            rows = []
            listReady = false
        }
        // поиск без копии: прежний список остаётся до ответа
    }

    private func diskList(_ key: String, q: String) -> ListResp? {
        guard q.isEmpty, let d = DiskCache.read("mail.list." + key), let r = try? API.decode(ListResp.self, d) else { return nil }
        lists[key] = r
        return r
    }

    /// только изменения: одинаковый ответ список не трогает (без прыжков и сброса прокрутки)
    private func applyList(_ r: ListResp) {
        if rows != r.rows { rows = r.rows }
        let u: Int = r.counts?.unread ?? 0
        let rp: Int = r.counts?.replies ?? 0
        if unread != u { unread = u }
        if replies != rp { replies = rp }
    }

    func loadList(folder: String, box: Int?, q: String, fixture: Bool, force: Bool = true) async {
        if fixture { return }
        showList(folder: folder, box: box, q: q)
        let key: String = Self.keyFor(folder: folder, box: box, q: q)
        await gate.run("list." + key, force: force || !q.isEmpty) { [self] in
            await fetchList(key: key, folder: folder, box: box, q: q)
        }
    }

    private func fetchList(key: String, folder: String, box: Int?, q: String) async -> Bool {
        var query: [URLQueryItem] = [URLQueryItem(name: "folder", value: folder)]
        if let box { query.append(URLQueryItem(name: "box", value: String(box))) }
        if !q.isEmpty { query.append(URLQueryItem(name: "q", value: q)) }
        let acc: String? = DiskCache.account
        loading = true
        defer { loading = false }
        do {
            let d: Data = try await API.send("GET", "/api/cabinet/mail/list/", query: query)
            let r: ListResp = try API.decode(ListResp.self, d)
            guard acc == DiskCache.account else { return false }
            lists[key] = r
            if q.isEmpty { DiskCache.write(d, "mail.list." + key) }
            // пока грузилось, могли переключить папку — тогда этот ответ только в копию
            if listKey == key {
                applyList(r)
                listReady = true
            }
            loadError = nil
            return true
        } catch let e as APIError where e.status == 403 {
            blocked = e.message
            return false
        } catch {
            guard acc == DiskCache.account else { return false }
            if listKey == key { listReady = true }
            if !isCancellation(error) { loadError = friendly(error) }
            return false
        }
    }

    /// переписка из памяти или с телефона — показать сразу, до ответа сервера
    func cachedThread(_ id: Int) -> [ThreadMsg]? {
        if let t = threads[id] { return t }
        guard let d = DiskCache.read("mail.thread.\(id)"), let r = try? API.decode(ThreadResp.self, d), !r.rows.isEmpty else { return nil }
        threads[id] = r.rows
        return r.rows
    }

    /// свежая переписка с сервера; [] — не получилось (копию тогда не трогаем)
    func thread(_ id: Int, fixture: Bool) async -> [ThreadMsg] {
        if fixture { return Self.fixtureThread }
        if let i = rows.firstIndex(where: { $0.id == id }) { rows[i].seen = true }
        let acc: String? = DiskCache.account
        guard let d = try? await API.send("GET", "/api/cabinet/mail/thread/", query: [URLQueryItem(name: "id", value: String(id))]),
              let r = try? API.decode(ThreadResp.self, d), acc == DiskCache.account else { return [] }
        if !r.rows.isEmpty {
            threads[id] = r.rows
            DiskCache.write(d, "mail.thread.\(id)")
        }
        return r.rows
    }

    /// references — все Message-ID переписки через пробел (корень первым): по ним почтовый движок держит ответ в той же цепочке.
    func send(box: Int, to: String, subject: String, text: String, replyTo: String?, references: String? = nil) async throws {
        var body: [String: Any] = ["box": box, "to": to, "subject": subject, "text": text]
        if let replyTo {
            body["inReplyTo"] = replyTo
            let refs: String = (references?.isEmpty == false ? references : nil) ?? replyTo
            body["references"] = refs
        }
        try await API.send("POST", "/api/cabinet/mail/send/", json: body)
    }

    /// прочитано/непрочитано/пометить (POST /action) — сразу в списке, на сервере следом
    func act(_ m: MailMsg, _ action: String, fixture: Bool) async -> Bool {
        guard let i = rows.firstIndex(where: { $0.id == m.id }) else { return false }
        if action == "seen" || action == "unseen" { rows[i].seen = action == "seen" }
        if action == "flag" || action == "unflag" { rows[i].flagged = action == "flag" }
        if fixture { return true }
        guard let box = m.mailboxId else { return false }
        do { try await API.send("POST", "/api/cabinet/mail/action/", json: ["box": box, "ids": [m.id], "action": action]); return true }
        catch { return false }
    }

    /// перевод (POST /translate): текст → язык `to`; ответ — перевод и язык оригинала.
    /// 2 попытки с паузой (сеть, таймаут, 5xx — в т. ч. «переводчик занят»); 4xx (лимит, нет доступа) — сразу ошибка.
    func translate(_ text: String, to: String, fixture: Bool) async throws -> (text: String, from: String) {
        if fixture {
            if to != MailLang.mine { return ("¡Hola! Sí, el jueves a las 11 nos viene bien.", MailLang.mine) }
            let mineText: String = FixtureText.english ? "Hi! Thanks for writing. Yes, please send us the plan. Shall we go over it on Thursday at 11?" : "Привет! Спасибо за письмо. Давайте созвонимся в четверг в 11."
            return (mineText, "es")
        }
        var last: Error = APIError(status: 0, message: String(localized: "не получилось перевести"))
        for attempt in 0..<2 {
            if attempt > 0 {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
            do {
                let r: TranslateResp = try await API.post(TranslateResp.self, "/api/cabinet/mail/translate/", json: ["text": text, "to": to], timeout: 35)
                return (r.text, r.from ?? "?")
            } catch {
                last = error
                if Task.isCancelled || !Self.retryable(error) { throw error }
            }
        }
        throw last
    }

    private static func retryable(_ error: Error) -> Bool {
        if let e = error as? APIError { return e.status == 0 || e.status >= 500 }
        return (error as NSError).domain == NSURLErrorDomain
    }

    /// уже готовый перевод письма (память или телефон) — показать сразу, без запроса
    func cachedTranslation(id: Int, to: String) -> MailTranslation? {
        let key: String = "\(id).\(to)"
        if let t = translations[key] { return t }
        guard let d = DiskCache.read("mail.tr." + key), let t = try? JSONDecoder().decode(MailTranslation.self, from: d) else { return nil }
        translations[key] = t
        return t
    }

    /// Перевод входящего письма: из копии, иначе запрос. Пока идёт запрос для этого письма — второй не шлём, ждём первый.
    func translateMessage(id: Int, text: String, to: String, fixture: Bool) async throws -> MailTranslation {
        let key: String = "\(id).\(to)"
        if let t = cachedTranslation(id: id, to: to) { return t }
        if let running = translating[key] { return try await running.value }
        let task: Task<MailTranslation, Error> = Task { @MainActor in
            let r: (text: String, from: String) = try await self.translate(text, to: to, fixture: fixture)
            return MailTranslation(text: r.text, from: r.from)
        }
        translating[key] = task
        defer { translating[key] = nil }
        let t: MailTranslation = try await task.value
        translations[key] = t
        if !fixture, let d = try? JSONEncoder().encode(t) { DiskCache.write(d, "mail.tr." + key) }
        return t
    }

    func loadCampaigns(fixture: Bool, force: Bool = true) async {
        if fixture { return }
        await gate.run("campaigns", force: force) { [self] in
            let acc: String? = DiskCache.account
            guard let d = try? await API.send("GET", "/api/cabinet/mail/campaigns/"), let r = try? API.decode(CampResp.self, d) else {
                campaignsReady = true
                return false
            }
            guard acc == DiskCache.account else { return false }
            if campaigns != r.rows { campaigns = r.rows }
            campaignsReady = true
            DiskCache.write(d, "mail.campaigns")
            return true
        }
    }

    func campaign(_ c: Campaign, _ action: String) async throws {
        try await API.send("POST", "/api/cabinet/mail/campaigns/\(c.id)/\(action)/")
        await loadCampaigns(fixture: false)
    }

    private struct CampOne: Decodable { let campaign: Campaign? }

    /// правка рассылки: только изменённые поля (name, steps, boxIds, dailyCap, windowFrom, windowTo, weekdaysOnly)
    func editCampaign(_ id: Int, _ body: [String: Any]) async throws {
        let r = try await API.post(CampOne.self, "/api/cabinet/mail/campaigns/\(id)/edit/", json: body)
        if let c = r.campaign { put(c) } else { await loadCampaigns(fixture: false) }
    }

    /// удалить (только не идущую — иначе сервер ответит 409): сразу убираем из списка, ошибка — возвращаем
    @discardableResult
    func deleteCampaign(_ id: Int, fixture: Bool) async throws -> Campaign? {
        guard let i = campaigns.firstIndex(where: { $0.id == id }) else { return nil }
        let removed: Campaign = campaigns[i]
        withAnimation(.spring(response: 0.3)) { _ = campaigns.remove(at: i) }
        if fixture { return removed }
        do {
            try await API.send("POST", "/api/cabinet/mail/campaigns/\(id)/delete/")
        } catch {
            withAnimation(.spring(response: 0.3)) { put(removed) }
            throw error
        }
        return removed
    }

    /// вернуть удалённую (сервер хранит сутки)
    func restoreCampaign(_ old: Campaign, fixture: Bool) async throws {
        if fixture { withAnimation(.spring(response: 0.3)) { put(old) }; return }
        let r = try await API.post(CampOne.self, "/api/cabinet/mail/campaigns/\(old.id)/restore/")
        withAnimation(.spring(response: 0.3)) { put(r.campaign ?? old) }
        if r.campaign == nil { await loadCampaigns(fixture: false) }
    }

    /// заменить или вставить рассылку (список — новые сверху, как отдаёт сервер)
    private func put(_ c: Campaign) {
        if let i = campaigns.firstIndex(where: { $0.id == c.id }) { campaigns[i] = c; return }
        let at: Int = campaigns.firstIndex(where: { $0.id < c.id }) ?? campaigns.count
        campaigns.insert(c, at: at)
    }

    // MARK: - данные для снимков CI (-fixture)
    static var fixtureThread: [ThreadMsg] { FixtureText.english ? fixtureThreadEN : fixtureThreadRU }
    private static let fixtureThreadRU: [ThreadMsg] = [
        ThreadMsg(id: 1, mailboxId: 1, folder: "sent", messageId: "<a@x>", fromAddr: "hi@studio.ru", fromName: "Студия", toAddr: "hello@mayak.ru",
                  subject: "Меню на сайте", body: "Здравствуйте! Заметил, что на вашем сайте сложно найти меню с телефона. Могу показать, как это поправить за пару дней — удобно созвониться?", date: "2026-11-10T09:12:00Z"),
        ThreadMsg(id: 2, mailboxId: 1, folder: "inbox", messageId: "<b@x>", fromAddr: "marta@cafe.es", fromName: "Marta · Café Sol", toAddr: "hi@studio.ru",
                  subject: "Re: Меню на сайте", body: "¡Hola! Gracias por escribir. ¿Podemos hablar el jueves a las 11?\n\nSaludos,\nMarta\n\nEl mar, 10 nov 2026 a las 12:12, Студия <hi@studio.ru> escribió:\n> Здравствуйте! Заметил, что на вашем сайте сложно найти меню с телефона.", date: "2026-11-11T07:40:00Z"),
    ]
    private static let fixtureThreadEN: [ThreadMsg] = [
        ThreadMsg(id: 1, mailboxId: 1, folder: "sent", messageId: "<a@x>", fromAddr: "hi@northstudio.co.uk", fromName: "North Studio", toAddr: "marta@cafe.es",
                  subject: "Your menu on mobile", body: "Hi Marta! I noticed the menu on your website is hard to find on a phone. I can show you how to fix it in a couple of days. Shall I send a short plan?", date: "2026-11-10T09:12:00Z"),
        ThreadMsg(id: 2, mailboxId: 1, folder: "inbox", messageId: "<b@x>", fromAddr: "marta@cafe.es", fromName: "Marta · Café Sol", toAddr: "hi@northstudio.co.uk",
                  subject: "Re: Your menu on mobile", body: "¡Hola! Gracias por escribir. Sí, envíenos el plan, por favor. ¿Lo vemos el jueves a las 11?\n\nSaludos,\nMarta\n\nEl mar, 10 nov 2026 a las 12:12, North Studio <hi@northstudio.co.uk> escribió:\n> Hi Marta! I noticed the menu on your website is hard to find on a phone.", date: "2026-11-11T07:40:00Z"),
    ]
    static func fill(_ m: MailStore) {
        let en: Bool = FixtureText.english
        let boxAddr: String = en ? "hi@northstudio.co.uk" : "hi@studio.ru"
        m.boxes = [MailBox(id: 1, address: boxAddr, name: en ? "North Studio" : "Студия", dailyLimit: 40, sentToday: 12, unread: 2, syncOk: true, syncError: nil),
                   MailBox(id: 2, address: en ? "sales@northstudio.co.uk" : "sales@studio.ru", name: nil, dailyLimit: 30, sentToday: 0, unread: 0, syncOk: true, syncError: nil)]
        let now: String = ISO8601DateFormatter().string(from: .now)
        if en {
            m.rows = [
                MailMsg(id: 2, mailboxId: 1, fromAddr: "hello@example.com", fromName: "The Lighthouse Café", to: nil, subject: "Re: Menu on your website",
                        snippet: "Good afternoon! Yes, let's do it. Does tomorrow after 3 pm work for you?", date: now, seen: false, hasAtt: false, isReply: true),
                MailMsg(id: 3, mailboxId: 1, fromAddr: "info@example.net", fromName: "Bean & Grind", to: nil, subject: "Re: Online booking",
                        snippet: "Thanks, not right now. Please write to us in spring.", date: "2026-11-09T12:00:00Z", seen: true, hasAtt: false, isReply: true),
            ]
        } else {
            m.rows = [
                MailMsg(id: 2, mailboxId: 1, fromAddr: "hello@mayak.ru", fromName: "Кофейня «Маяк»", to: nil, subject: "Re: Меню на сайте",
                        snippet: "Добрый день! Да, давайте. Завтра после 15:00 удобно?", date: now, seen: false, hasAtt: false, isReply: true),
                MailMsg(id: 3, mailboxId: 1, fromAddr: "info@zerno.ru", fromName: "Зерно", to: nil, subject: "Re: Онлайн-запись",
                        snippet: "Спасибо, пока не актуально, напишите весной.", date: "2026-11-09T12:00:00Z", seen: true, hasAtt: false, isReply: true),
            ]
        }
        m.unread = 1; m.replies = 2
        m.listReady = true; m.campaignsReady = true; m.boxesReady = true
        if en {
            m.campaigns = [
                Campaign(id: 1, name: "London coffee shops", status: "running", total: 120, sent: 64, replied: 5, errors: 1, today: 12, dailyCap: 40, listName: "batch of November 11",
                         steps: [CampaignStep(subject: "Menu on your website", body: "Hi! {{сообщение}}\n\nIf you're interested, I'm happy to answer questions and show examples.", delayDays: 0),
                                 CampaignStep(subject: "", body: "Hi again! Just following up on my email above. Would this week work for a short reply?", delayDays: 3)],
                         mailboxIds: [1], windowFrom: 10, windowTo: 19, weekdaysOnly: true, stepsSent: [60, 4]),
                Campaign(id: 2, name: "Bakeries · autumn", status: "paused", total: 48, sent: 20, replied: 2, errors: 0, today: 0, dailyCap: 30, listName: "London bakeries",
                         steps: [CampaignStep(subject: "Online orders", body: "Hi! {{сообщение}}", delayDays: 0)], mailboxIds: [1], windowFrom: 9, windowTo: 18, weekdaysOnly: false),
            ]
        } else {
            m.campaigns = [
                Campaign(id: 1, name: "Кофейни Казани", status: "running", total: 120, sent: 64, replied: 5, errors: 1, today: 12, dailyCap: 40, listName: "выдача 11 ноября",
                         steps: [CampaignStep(subject: "Меню на сайте", body: "Здравствуйте! {{сообщение}}\n\nЕсли интересно — отвечу на вопросы и покажу примеры.", delayDays: 0),
                                 CampaignStep(subject: "", body: "Добрый день! Напомню о письме выше — удобно ли созвониться на этой неделе?", delayDays: 3)],
                         mailboxIds: [1], windowFrom: 10, windowTo: 19, weekdaysOnly: true, stepsSent: [60, 4]),
                Campaign(id: 2, name: "Пекарни · осень", status: "paused", total: 48, sent: 20, replied: 2, errors: 0, today: 0, dailyCap: 30, listName: "Пекарни Казань",
                         steps: [CampaignStep(subject: "Онлайн-заказ", body: "Здравствуйте! {{сообщение}}", delayDays: 0)], mailboxIds: [1], windowFrom: 9, windowTo: 18, weekdaysOnly: false),
            ]
        }
    }
}

struct MailView: View {
    @Environment(Store.self) private var store
    /// почта живёт в Store: при переключении вкладок не пересоздаётся (раньше грузилась заново при каждом входе)
    private var mail: MailStore { store.mail }
    @State private var view = "letters"
    @State private var folder = "inbox"
    @State private var box: Int?
    @State private var q = ""
    @State private var openId: Int?
    @State private var searchTask: Task<Void, Never>?
    @State private var composing = false
    @State private var settingsCamp: Campaign?
    @State private var deleteCamp: Campaign?
    /// снимок 23: сразу открыть редактор письма цепочки
    @State private var openStep: Int?
    @Environment(\.openURL) private var openURL

    private static let folders: [(String, String)] = [
        ("inbox", String(localized: "входящие")), ("unread", String(localized: "непрочитанные")), ("replies", String(localized: "ответы на рассылки")),
        ("starred", String(localized: "помеченные")), ("sent", String(localized: "исходящие")), ("spam", String(localized: "спам")),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom) {
                Text("почта").font(Typo.display(30)).tracking(-1).foregroundStyle(Pal.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if mail.blocked == nil && !mail.boxes.isEmpty {
                    PillButton(height: 34, action: { composing = true }) {
                        Image(systemName: "square.and.pencil").iconFont(14, .semibold)
                        Text("написать")
                    }
                    .accessibilityLabel(Text("написать письмо"))
                }
            }
            .padding(.horizontal, 20).padding(.top, 22)
            if let b = mail.blocked {
                blockedView(b)
            } else {
                GlassSegment(items: viewItems, selection: $view)
                    .padding(.horizontal, 16).padding(.top, 14)
                switch view {
                case "campaigns": campaignsView
                case "boxes": boxesView
                default: lettersView
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .metalBackground(.corner)
        .task {
            // экран пересоздан (переключение вкладок): список своей папки из памяти/копии — сразу, до сети
            if !store.fixture { mail.restore(); mail.showList(folder: folder, box: box, q: q) }
            mail.loadHidden(account: store.user?.email ?? "")
            if store.fixture, let f = store.fixtureMail {
                MailStore.fill(mail)
                switch f {
                case "thread": openId = 2
                case "camp-settings": view = "campaigns"; settingsCamp = mail.campaigns.first
                case "camp-delete": view = "campaigns"; deleteCamp = mail.campaigns.first
                case "camp-step": view = "campaigns"; openStep = 1; settingsCamp = mail.campaigns.first
                default: composing = true
                }
            }
            // копия — сразу, свежее — в фоне; загруженное меньше минуты назад не перезапрашиваем
            await mail.refresh(folder: folder, box: box, q: q, fixture: store.fixture, force: false)
        }
        .onChange(of: folder) { _, _ in reload() }
        .onChange(of: box) { _, _ in reload() }
        .sheet(item: openBox) { (b: IdBox) in
            ThreadView(id: b.id, mail: mail, boxes: mail.boxes)
        }
        .sheet(isPresented: $composing) { ComposeView(mail: mail, boxes: mail.boxes, preferBox: box) }
        .sheet(item: $settingsCamp) { (c: Campaign) in CampaignEditSheet(c: c, mail: mail, openStep: openStep) }
        .confirmationDialog(deleteCampTitle, isPresented: deleteShown, titleVisibility: .visible, presenting: deleteCamp) { (c: Campaign) in
            Button(c.running ? "поставить на паузу и удалить" : "удалить", role: .destructive) { deleteCampaign(c) }
            Button("отмена", role: .cancel) {}
        } message: { (c: Campaign) in
            Text(c.running ? "Рассылка сейчас идёт — удалить можно только остановленную. Сначала она встанет на паузу, потом удалится. База получателей и история писем сохранятся, сразу после удаления можно нажать «отменить»." : "База получателей и история писем сохранятся. Сразу после удаления можно нажать «отменить».")
        }
    }

    // Binding листа переписки и диалога удаления — свойствами с явными типами (не внутри длинной цепочки модификаторов)
    private var openBox: Binding<IdBox?> {
        Binding<IdBox?>(get: { openId.map { (i: Int) -> IdBox in IdBox(id: i) } }, set: { (v: IdBox?) in openId = v?.id })
    }
    private var deleteShown: Binding<Bool> {
        Binding<Bool>(get: { deleteCamp != nil }, set: { (v: Bool) in if !v { deleteCamp = nil } })
    }

    /// вкладки почты (вынесено из body: массив кортежей с тернарником и String(localized:) — тяжёлое выражение для type-checker)
    private var viewItems: [(String, String)] {
        let letters: String = mail.unread > 0 ? String(localized: "письма · \(mail.unread)") : String(localized: "письма")
        let campaigns: String = String(localized: "рассылки")
        let boxes: String = String(localized: "мои почты")
        return [("letters", letters), ("campaigns", campaigns), ("boxes", boxes)]
    }

    private var deleteCampTitle: String {
        guard let c = deleteCamp else { return "" }
        return String(localized: "Удалить рассылку «\(c.name)»?")
    }

    /// Удалить по-настоящему (сервер, мягко — сутки можно вернуть). Идущую сначала ставим на паузу: сервер удаляет только остановленную.
    private func deleteCampaign(_ c: Campaign) {
        if !store.fixture && !NetMonitor.shared.online {
            store.show(String(localized: "нет сети — удалить рассылку можно, когда связь вернётся"), ok: false)
            return
        }
        let wasRunning: Bool = c.running
        let name: String = c.name
        let fixture: Bool = store.fixture
        Task {
            if wasRunning && !fixture {
                do { try await mail.campaign(c, "pause") } catch {
                    store.show((error as? APIError)?.message ?? String(localized: "не получилось остановить рассылку"), ok: false)
                    return
                }
            }
            do {
                guard let removed = try await mail.deleteCampaign(c.id, fixture: fixture) else { return }
                store.show(String(localized: "рассылка «\(name)» удалена"), undo: {
                    Task { @MainActor in await restoreCampaign(removed, start: wasRunning) }
                }, undoSeconds: Guide.undoSeconds)
            } catch {
                let why: String = (error as? APIError)?.message ?? String(localized: "не получилось удалить рассылку")
                store.show(wasRunning ? String(localized: "рассылка на паузе, но не удалилась: \(why)") : why, ok: false)
            }
        }
    }

    /// «отменить» удаление: вернуть рассылку и, если шла, запустить снова
    @MainActor private func restoreCampaign(_ c: Campaign, start: Bool) async {
        do { try await mail.restoreCampaign(c, fixture: store.fixture) } catch {
            store.show((error as? APIError)?.message ?? String(localized: "не получилось вернуть рассылку"), ok: false)
            return
        }
        if start && !store.fixture {
            do { try await mail.campaign(c, "start") } catch {
                store.show(String(localized: "рассылка вернулась, но не запустилась — нажмите «запустить»"), ok: false)
                return
            }
        }
        store.show(String(localized: "рассылка вернулась"))
    }

    private func folderCount(_ f: String) -> String? {
        switch f {
        case "inbox", "unread": return mail.unread > 0 ? "\(mail.unread)" : nil
        case "replies": return mail.replies > 0 ? "\(mail.replies)" : nil
        default: return nil
        }
    }

    /// смена папки / ящика / поиска: копия папки — сразу, запрос — если она старше минуты (поиск — всегда)
    private func reload() { Task { await mail.loadList(folder: folder, box: box, q: q, fixture: store.fixture, force: false) } }

    private func blockedView(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "envelope.badge").iconFont(30).foregroundStyle(Pal.ink.opacity(0.6))
            Text(text).font(Typo.body(16)).foregroundStyle(Pal.ink).lineSpacing(3)
            Text("Рабочая почта: свои адреса, ответы клиентов и рассылки по компаниям прямо отсюда.").font(Typo.body(14)).foregroundStyle(Pal.fg2)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .glassRect(24)
        .padding(.horizontal, 16).padding(.top, 18)
    }

    @ViewBuilder private var lettersView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.folders.indices, id: \.self) { i in
                    let f = Self.folders[i]
                    Chip(text: f.1, count: folderCount(f.0), on: folder == f.0, height: 32, fontSize: 13) { folder = f.0 }
                }
                if mail.boxes.count > 1 {
                    Menu {
                        Button("все почты") { box = nil }
                        ForEach(mail.boxes) { b in Button(b.address) { box = b.id } }
                    } label: {
                        HStack(spacing: 4) {
                            Text(mail.boxes.first { $0.id == box }?.address ?? String(localized: "все почты")).lineLimit(1)
                            Image(systemName: "chevron.down").iconFont(10, .bold)
                        }
                        .font(Typo.body(13, .semibold)).foregroundStyle(Pal.ink)
                        .padding(.horizontal, 12).frame(minHeight: 32).background(Capsule().fill(Pal.surface.opacity(0.6)))
                        .frame(minHeight: 44).contentShape(Rectangle())
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 2)
        }
        .padding(.top, 12)
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").iconFont(15).foregroundStyle(Pal.ink.opacity(0.6)).accessibilityHidden(true)
            TextField("", text: $q, prompt: Text("поиск по письмам").foregroundColor(Pal.fg3))
                .font(Typo.body(15)).foregroundStyle(Pal.ink).textInputAutocapitalization(.never).autocorrectionDisabled()
                .onChange(of: q) { _, _ in
                    searchTask?.cancel()
                    searchTask = Task { try? await Task.sleep(nanoseconds: 500_000_000); if !Task.isCancelled { reload() } }
                }
            if !q.isEmpty {
                Button { q = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Pal.fg3).frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel(Text("очистить поиск"))
            }
        }
        .padding(.horizontal, 14).frame(minHeight: 44)
        .glassCapsule()
        .padding(.horizontal, 16).padding(.top, 10)
        ScrollView {
            if let e = mail.loadError, !mail.rows.isEmpty {
                StaleNote(why: e).padding(.horizontal, 20).padding(.top, 10)
            }
            LazyVStack(spacing: 0) {
                ForEach(Array(mail.rows.enumerated()), id: \.element.id) { i, m in
                    Button { openId = m.id } label: { MailRow(m: m, first: i == 0, sent: folder == "sent") }
                        .buttonStyle(RowPressStyle())
                        .contextMenu {
                            Button { Task { _ = await mail.act(m, m.seen ? "unseen" : "seen", fixture: store.fixture) } } label: {
                                Label(m.seen ? "непрочитанное" : "прочитанное", systemImage: m.seen ? "envelope.badge" : "envelope.open")
                            }
                            Button { Task { _ = await mail.act(m, m.flagged ? "unflag" : "flag", fixture: store.fixture) } } label: {
                                Label(m.flagged ? "снять пометку" : "пометить", systemImage: m.flagged ? "star.slash" : "star")
                            }
                        }
                }
                if mail.rows.isEmpty { lettersEmpty }
            }
            .glassRect(24)
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 130)
        }
        .refreshable { await mail.refresh(folder: folder, box: box, q: q, fixture: store.fixture, force: true) }
    }

    @ViewBuilder private var lettersEmpty: some View {
        if !mail.listReady || (mail.loading && !q.isEmpty) {
            SkeletonRows(count: 6)
        } else if !q.isEmpty {
            EmptyState(icon: "magnifyingglass", title: String(localized: "ничего не нашли"), text: String(localized: "Попробуйте другое слово или другую папку."),
                       action: String(localized: "очистить поиск")) { q = "" }
        } else if folder == "replies" {
            EmptyState(icon: "arrowshape.turn.up.left", title: String(localized: "ответов пока нет"),
                       text: String(localized: "Они появятся здесь, когда компании ответят на рассылку. Обычно первые ответы приходят в течение пары дней."))
        } else if folder == "sent" {
            EmptyState(icon: "paperplane", title: String(localized: "исходящих пока нет"), text: String(localized: "Здесь будут письма, которые вы отправили."),
                       action: mail.boxes.isEmpty ? nil : String(localized: "написать письмо")) { composing = true }
        } else {
            EmptyState(icon: "tray", title: String(localized: "здесь пусто"),
                       text: String(localized: "Новые письма и ответы компаний будут приходить сюда. Список обновляется, если потянуть его вниз."),
                       action: mail.boxes.isEmpty ? nil : String(localized: "написать письмо")) { composing = true }
        }
    }

    @ViewBuilder private var campaignsView: some View {
        let visible: [Campaign] = mail.campaigns
        ScrollView {
            VStack(spacing: 10) {
                HintCard(key: Guide.hintMail, icon: "envelope.badge",
                         title: String(localized: "как устроена рассылка"),
                         text: String(localized: "Письма уходят сами — в окне отправки и не больше дневного лимита. «⋯» на карточке — настройки и удаление. Новую рассылку собирают из компаний: «выбрать» → «в рассылку»."))
                ForEach(visible) { (c: Campaign) in
                    CampaignCard(c: c, mail: mail, onSettings: { settingsCamp = c }, onDelete: { deleteCamp = c })
                }
                if visible.isEmpty && !mail.campaignsReady {
                    SkeletonRows(count: 2, cards: true)
                } else if visible.isEmpty {
                    EmptyState(icon: "paperplane.circle", title: String(localized: "рассылок пока нет"),
                               text: String(localized: "Откройте «компании», нажмите «выбрать», отметьте нужные и нажмите «в рассылку» — письма уйдут сами, в рабочие часы."),
                               action: String(localized: "к компаниям")) { store.tab = .leads }
                        .glassRect(24)
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 130)
        }
        .refreshable { await mail.loadCampaigns(fixture: store.fixture, force: true) }
    }

    @ViewBuilder private var boxesView: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(mail.boxes.enumerated()), id: \.element.id) { i, b in
                    GroupRow(first: i == 0) {
                        Image(systemName: b.syncOk == false ? "exclamationmark.triangle" : "envelope").iconFont(16).frame(width: 24).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(b.address).lineLimit(1)
                            Text(boxLine(b)).font(Typo.body(13)).foregroundStyle(b.syncOk == false ? Pal.danger : Pal.fg2).lineLimit(2)
                        }
                        Spacer()
                        if let u = b.unread, u > 0 { Text("\(u)").font(Typo.mono(12, .semibold)).foregroundStyle(Pal.onInk).padding(.horizontal, 8).frame(minHeight: 22).background(Capsule().fill(Pal.ink)) }
                    }
                }
                if mail.boxes.isEmpty && !mail.boxesReady {
                    SkeletonRows(count: 2)
                } else if mail.boxes.isEmpty {
                    EmptyState(icon: "envelope", title: String(localized: "почт пока нет"),
                               text: String(localized: "«Мои почты» — адреса, с которых уходят письма и рассылки. Подключают их в веб-кабинете: раздел «почта»."),
                               action: String(localized: "открыть веб-кабинет")) { openURL(Guide.webCabinet) }
                }
            }
            .glassRect(24)
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 130)
        }
        .refreshable { await mail.loadBoxes(fixture: store.fixture, force: true) }
    }

    private func boxLine(_ b: MailBox) -> String {
        if b.syncOk == false {
            let why: String = b.syncError ?? String(localized: "ошибка входа")
            return String(localized: "не синхронизируется: \(why)")
        }
        let sent: Int = b.sentToday ?? 0
        if let lim = b.dailyLimit { return String(localized: "сегодня отправлено \(sent) из \(lim)") }
        return String(localized: "сегодня отправлено \(sent)")
    }
}

private struct IdBox: Identifiable { let id: Int }

struct MailRow: View {
    let m: MailMsg
    let first: Bool
    let sent: Bool
    var body: some View {
        VStack(spacing: 0) {
            if !first { Rectangle().fill(Pal.line).frame(height: 0.5).padding(.leading, 16) }
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(m.seen ? Color.clear : Pal.ink).frame(width: 8, height: 8).padding(.top, 7)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(sent ? String(localized: "кому: \(m.to ?? "")") : m.who).font(Typo.body(15, m.seen ? .regular : .semibold)).lineLimit(1)
                        Spacer(minLength: 6)
                        if m.flagged { Image(systemName: "star.fill").iconFont(11).foregroundStyle(Pal.ink.opacity(0.7)) }
                        Text(MailDate.short(m.date)).font(Typo.mono(12, .medium)).foregroundStyle(Pal.fg3)
                    }
                    HStack(spacing: 6) {
                        if m.isReply { Text("ответ").font(Typo.body(13, .semibold)).padding(.horizontal, 7).frame(minHeight: 18).background(Capsule().fill(Pal.ink.opacity(0.08))) }
                        Text(m.subject.isEmpty ? String(localized: "(без темы)") : m.subject).font(Typo.body(14, .semibold)).lineLimit(1)
                        if m.hasAtt { Image(systemName: "paperclip").iconFont(12).foregroundStyle(Pal.fg3) }
                    }
                    Text(m.snippet).font(Typo.body(13)).foregroundStyle(Pal.fg2).lineLimit(2)
                }
            }
            .foregroundStyle(Pal.ink)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
    }
}

struct CampaignCard: View {
    @Environment(Store.self) private var store
    let c: Campaign
    let mail: MailStore
    var onSettings: () -> Void = {}
    var onDelete: () -> Void = {}
    @State private var busy = false
    @State private var confirmStart = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text(c.name).font(Typo.display(16)).foregroundStyle(Pal.ink).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(c.statusTitle).font(Typo.body(13, .semibold))
                    .foregroundStyle(c.running ? Pal.onInk : Pal.ink)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(c.running ? Pal.ink : Pal.ink.opacity(0.08)))
                    .padding(.top, 10)
                Menu {
                    Button(action: onSettings) { Label("настройки", systemImage: "slider.horizontal.3") }
                    Button(role: .destructive, action: onDelete) { Label("удалить рассылку", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").iconFont(17, .semibold).foregroundStyle(Pal.ink)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel(Text("ещё: настройки и удаление"))
            }
            if let l = c.listName { Text(l).font(Typo.body(14)).foregroundStyle(Pal.fg2) }
            Bar(fraction: c.total > 0 ? Double(c.sent) / Double(c.total) : 0)
                .accessibilityHidden(true)
            HStack(alignment: .top, spacing: 14) {
                stat("\(c.sent) / \(c.total)", String(localized: "отправлено"))
                stat("\(c.replied)", String(localized: "ответили"))
                stat(todayText, String(localized: "сегодня"))
                if c.errors > 0 { stat("\(c.errors)", String(localized: "ошибок")) }
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 8) {
                if !c.finished {
                    PillButton(height: 40, action: tapToggle) {
                        Image(systemName: c.running ? "pause.fill" : "play.fill").iconFont(12)
                        Text(busy ? "…" : (c.running ? "пауза" : "запустить"))
                    }
                }
                PillButton(height: 40, action: onSettings) {
                    Image(systemName: "slider.horizontal.3").iconFont(12)
                    Text("настройки")
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassRect(24)
        .confirmationDialog("Запустить рассылку «\(c.name)»?", isPresented: $confirmStart, titleVisibility: .visible) {
            Button("запустить сейчас") { toggle() }
            Button("отмена", role: .cancel) {}
        } message: {
            Text(startMessage)
        }
    }

    private var startMessage: String {
        let cap: String = c.dailyCap.map { String(localized: "до \($0) писем в день") } ?? String(localized: "по дневному лимиту почт")
        if c.weekdaysOnly == true {
            return String(localized: "Письма начнут уходить сразу: с \(c.windowText), \(cap), только по будням. Остановить можно кнопкой «пауза».")
        }
        return String(localized: "Письма начнут уходить сразу: с \(c.windowText), \(cap), каждый день. Остановить можно кнопкой «пауза».")
    }

    private var todayText: String {
        if let cap = c.dailyCap { return "\(c.today)/\(cap)" }
        return "\(c.today)"
    }
    private func stat(_ v: String, _ t: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(v).font(Typo.mono(15, .semibold)).foregroundStyle(Pal.ink)
            Text(t).font(Typo.body(13)).foregroundStyle(Pal.fg2)
        }
    }
    /// пауза — сразу; запуск — с подтверждением (письма уйдут реальным людям)
    private func tapToggle() {
        guard !busy else { return }
        if c.running { toggle() } else { confirmStart = true }
    }
    private func toggle() {
        guard !busy else { return }
        if store.fixture { store.show(c.running ? String(localized: "рассылка на паузе") : String(localized: "рассылка запущена")); return }
        busy = true
        let action = c.running ? "pause" : "start"
        Task {
            do { try await mail.campaign(c, action); store.show(action == "pause" ? String(localized: "рассылка на паузе") : String(localized: "рассылка запущена")) } catch { store.show((error as? APIError)?.message ?? String(localized: "не получилось"), ok: false) }
            busy = false
        }
    }
}

/// Письмо цепочки в редакторе: id — для списка и перехода к редактору письма.
struct StepDraft: Identifiable, Hashable {
    let id: UUID
    var subject: String
    var body: String
    var delayDays: Int
    /// сколько раз это письмо уже ушло (steps_sent) — такие письма убрать нельзя, правка коснётся только следующих
    let sent: Int
    init(subject: String, body: String, delayDays: Int, sent: Int) {
        self.id = UUID(); self.subject = subject; self.body = body; self.delayDays = delayDays; self.sent = sent
    }
}

/// Пределы правки рассылки — как в почтовом движке (метрика, povod_mail.mjs: cleanSteps/editPatch).
enum CampaignLimits {
    static let name = 120
    static let steps = 5
    static let subject = 300
    static let body = 20_000
    static let delay = 1...30
}

/// Настройки рассылки — редактируемые (POST /api/cabinet/mail/campaigns/:id/edit): название, письма цепочки 1–5,
/// мои почты, лимит в день, окно часов, только будни. Уходят только изменённые поля; ошибки сервера — как есть.
struct CampaignEditSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let c: Campaign
    let mail: MailStore
    /// открыть сразу редактор письма с этим номером (снимок 23)
    var openStep: Int? = nil

    @State private var name: String = ""
    @State private var steps: [StepDraft] = []
    @State private var boxIds: Set<Int> = []
    @State private var dailyCap: Int = 40
    @State private var windowFrom: Int = 10
    @State private var windowTo: Int = 19
    @State private var weekdaysOnly: Bool = true
    @State private var ready = false
    @State private var saving = false
    @State private var serverError: String?
    @State private var editing: UUID?
    @State private var confirmClose = false
    /// значения на момент открытия — с ними сравниваем, что изменилось (а не с сырыми полями рассылки)
    @State private var origBoxes: Set<Int> = []
    @State private var origCap: Int = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerBlock
                    if !problems.isEmpty || serverError != nil { problemsCard }
                    Cap(String(localized: "название"))
                    nameField
                    Cap(String(localized: "письма"))
                    stepsBlock
                    Cap(String(localized: "мои почты"))
                    boxesBlock
                    Cap(String(localized: "отправка"))
                    sendingBlock
                }
                .padding(.horizontal, 16).padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(MetalBackground(star: .none).ignoresSafeArea())
            .navigationTitle("настройки рассылки")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $editing) { (id: UUID) in
                StepEditorView(step: stepBinding(id), index: steps.firstIndex { $0.id == id } ?? 0)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("отмена") { if changed { confirmClose = true } else { dismiss() } }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { save() } label: {
                        if saving { ProgressView() } else { Text("сохранить").fontWeight(.semibold) }
                    }
                    .disabled(!canSave)
                    .accessibilityLabel(Text("сохранить настройки рассылки"))
                }
            }
            .confirmationDialog("Выйти без сохранения?", isPresented: $confirmClose, titleVisibility: .visible) {
                Button("выйти без сохранения", role: .destructive) { dismiss() }
                Button("продолжить правку", role: .cancel) {}
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(changed)
        .onAppear(perform: fill)
    }

    // MARK: - блоки

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(c.statusTitle) · отправлено \(c.sent) из \(c.total)").font(Typo.body(14)).foregroundStyle(Pal.fg2)
            if let l = c.listName { Text("база: \(l)").font(Typo.body(14)).foregroundStyle(Pal.fg2) }
            if c.sent > 0 || c.running {
                Label("Правка повлияет только на следующие письма — уже отправленные не изменятся.", systemImage: "info.circle")
                    .font(Typo.body(13)).foregroundStyle(Pal.fg2).padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !NetMonitor.shared.online {
                Label("Нет сети — сохранить можно, когда связь вернётся.", systemImage: "wifi.slash")
                    .font(Typo.body(13, .semibold)).foregroundStyle(Pal.danger).padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 4).padding(.top, 8)
    }

    private var problemsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let e = serverError {
                Text(e).font(Typo.body(14, .semibold)).foregroundStyle(Pal.danger).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(problems, id: \.self) { (p: String) in
                Label(p, systemImage: "exclamationmark.circle").font(Typo.body(14)).foregroundStyle(Pal.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassRect(24)
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
    }

    private var nameField: some View {
        TextField("название рассылки", text: $name, axis: .vertical)
            .font(Typo.body(16))
            .foregroundStyle(Pal.ink)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(minHeight: 48)
            .glassRect(24)
    }

    private var stepsBlock: some View {
        VStack(spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { i, st in
                stepCard(i, st)
            }
            if steps.count < CampaignLimits.steps {
                Button { addStep() } label: {
                    Label("добавить письмо", systemImage: "plus")
                        .font(Typo.body(15, .semibold)).foregroundStyle(Pal.ink)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .glassRect(24)
                }
                .buttonStyle(PressStyle())
            }
            Text("В цепочке до 5 писем. Следующее письмо уходит, только если компания не ответила.")
                .font(Typo.body(13)).foregroundStyle(Pal.fg2).padding(.horizontal, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stepHead(_ i: Int, _ st: StepDraft) -> String {
        if i == 0 { return String(localized: "письмо 1 — сразу") }
        let days: String = String(localized: "\(st.delayDays) дн.")
        return String(localized: "письмо \(i + 1) — через \(days), если не ответили")
    }

    private func stepCard(_ i: Int, _ st: StepDraft) -> some View {
        Button { haptic(); editing = st.id } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(stepHead(i, st)).font(Typo.body(13, .semibold)).foregroundStyle(Pal.fg2)
                        Spacer(minLength: 4)
                        Text("ушло: \(st.sent)").font(Typo.mono(12, .medium)).foregroundStyle(Pal.fg2)
                    }
                    if !st.subject.isEmpty {
                        Text(st.subject).font(Typo.body(16, .semibold)).foregroundStyle(Pal.ink).lineLimit(2)
                    }
                    Text(st.body.isEmpty ? String(localized: "(пустое письмо — добавьте текст)") : st.body)
                        .font(Typo.body(15)).foregroundStyle(st.body.isEmpty ? Pal.danger : Pal.ink).lineLimit(4)
                        .multilineTextAlignment(.leading)
                }
                Image(systemName: "chevron.right").iconFont(13, .semibold).foregroundStyle(Pal.fg3).padding(.top, 2)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassRect(24)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityHint(Text("открыть письмо для правки"))
        .contextMenu {
            if canRemove(i) {
                Button(role: .destructive) { removeStep(i) } label: { Label("убрать письмо", systemImage: "trash") }
            }
        }
    }

    private var boxesBlock: some View {
        VStack(spacing: 0) {
            if mail.boxes.isEmpty {
                GroupRow(first: true) { Text("почты не загрузились — потяните список почт вниз").foregroundStyle(Pal.fg2) }
            }
            ForEach(Array(mail.boxes.enumerated()), id: \.element.id) { i, b in
                boxRow(i, b)
            }
        }
        .glassRect(24)
    }

    private func boxRow(_ i: Int, _ b: MailBox) -> some View {
        let on: Bool = boxIds.contains(b.id)
        let limit: String = b.dailyLimit.map { String(localized: "до \($0) писем в день") } ?? ""
        return Button {
            haptic()
            if on { boxIds.remove(b.id) } else { boxIds.insert(b.id) }
            dailyCap = min(dailyCap, capMax)
        } label: {
            GroupRow(first: i == 0) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").iconFont(20)
                    .foregroundStyle(on ? Pal.ink : Pal.ink.opacity(0.3)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(b.address).lineLimit(1)
                    if !limit.isEmpty { Text(limit).font(Typo.body(13)).foregroundStyle(Pal.fg2) }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityAddTraits(on ? AccessibilityTraits([.isButton, .isSelected]) : AccessibilityTraits.isButton)
    }

    private var sendingBlock: some View {
        VStack(spacing: 0) {
            GroupRow(first: true) {
                Stepper(value: $dailyCap, in: 1...max(1, capMax)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("писем в день: \(dailyCap)")
                        Text("не больше \(capMax) — сумма лимитов выбранных почт").font(Typo.body(13)).foregroundStyle(Pal.fg2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 6)
            }
            GroupRow {
                Text("с").foregroundStyle(Pal.fg2)
                Picker("начало окна", selection: $windowFrom) {
                    ForEach(0..<24, id: \.self) { (h: Int) in Text(hour(h)).tag(h) }
                }
                .pickerStyle(.menu)
                Text("до").foregroundStyle(Pal.fg2)
                Picker("конец окна", selection: $windowTo) {
                    ForEach(1..<25, id: \.self) { (h: Int) in Text(hour(h)).tag(h) }
                }
                .pickerStyle(.menu)
                Spacer()
            }
            .frame(minHeight: 48)
            .accessibilityElement(children: .contain)
            GroupRow {
                VStack(alignment: .leading, spacing: 2) {
                    Text("только будни")
                    Text(weekdaysOnly ? "в субботу и воскресенье письма не уходят" : "письма уходят каждый день").font(Typo.body(13)).foregroundStyle(Pal.fg2)
                }
                Spacer()
                GlassSwitch(isOn: $weekdaysOnly)
            }
            .frame(minHeight: 52)
        }
        .glassRect(24)
    }

    private func hour(_ h: Int) -> String { String(format: "%02d:00", h) }

    // MARK: - данные

    /// сумма дневных лимитов выбранных почт (у почт без лимита — 500, как запас; точный предел проверит сервер)
    private var capMax: Int {
        let picked: [MailBox] = mail.boxes.filter { boxIds.contains($0.id) }
        let sum: Int = picked.reduce(0) { (acc: Int, b: MailBox) -> Int in acc + (b.dailyLimit ?? 500) }
        return max(1, sum)
    }

    private func fill() {
        guard !ready else { return }
        ready = true
        name = c.name
        steps = Self.drafts(c, withSent: true)
        if steps.isEmpty { steps = [StepDraft(subject: "", body: "", delayDays: 0, sent: 0)] }
        boxIds = Set(c.mailboxIds.isEmpty ? mail.boxes.map { $0.id } : c.mailboxIds)
        windowFrom = min(23, max(0, c.windowFrom ?? 10))
        windowTo = min(24, max(1, c.windowTo ?? 19))
        weekdaysOnly = c.weekdaysOnly ?? true
        dailyCap = max(1, c.dailyCap ?? min(40, capMax))
        origBoxes = boxIds
        origCap = dailyCap
        if let i = openStep, steps.indices.contains(i) {
            let id: UUID = steps[i].id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { editing = id }
        }
    }

    /// письма рассылки как черновики (пауза первого — 0, остальных — 1…30)
    static func drafts(_ c: Campaign, withSent: Bool) -> [StepDraft] {
        var out: [StepDraft] = []
        for (i, s) in c.steps.enumerated() {
            let delay: Int = i == 0 ? 0 : min(30, max(1, s.delayDays))
            out.append(StepDraft(subject: s.subject, body: s.body, delayDays: delay, sent: withSent ? c.sentCount(i) : 0))
        }
        return out
    }

    private func stepBinding(_ id: UUID) -> Binding<StepDraft> {
        Binding<StepDraft>(
            get: { steps.first { $0.id == id } ?? StepDraft(subject: "", body: "", delayDays: 1, sent: 0) },
            set: { (v: StepDraft) in if let i = steps.firstIndex(where: { $0.id == id }) { steps[i] = v } }
        )
    }

    private func addStep() {
        haptic()
        let s = StepDraft(subject: "", body: "", delayDays: 3, sent: 0)
        steps.append(s)
        editing = s.id
    }

    /// убрать можно только письмо, которое ещё не уходило, и не единственное
    private func canRemove(_ i: Int) -> Bool { steps.count > 1 && steps.indices.contains(i) && steps[i].sent == 0 && i > 0 }

    private func removeStep(_ i: Int) {
        guard canRemove(i) else { return }
        steps.remove(at: i)
    }

    /// понятные ошибки по пределам почтового движка
    private var problems: [String] {
        var out: [String] = []
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { out.append(String(localized: "назовите рассылку")) }
        if n.count > CampaignLimits.name { out.append(String(localized: "название — до \(CampaignLimits.name) знаков")) }
        if let first = steps.first, first.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out.append(String(localized: "у первого письма нужна тема"))
        }
        for (i, s) in steps.enumerated() {
            let num: Int = i + 1
            if s.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(String(localized: "в письме \(num) нет текста")) }
            if s.subject.count > CampaignLimits.subject { out.append(String(localized: "тема письма \(num) — до \(CampaignLimits.subject) знаков")) }
            if s.body.count > CampaignLimits.body { out.append(String(localized: "текст письма \(num) — до \(CampaignLimits.body) знаков")) }
            if i > 0 && !CampaignLimits.delay.contains(s.delayDays) { out.append(String(localized: "пауза перед письмом \(num) — от 1 до 30 дней")) }
        }
        if steps.count > CampaignLimits.steps { out.append(String(localized: "в цепочке — до 5 писем")) }
        if boxIds.isEmpty { out.append(String(localized: "выберите хотя бы одну почту")) }
        // верхний предел — только если почты загружены и лимит или почты меняли (точнее проверит сервер)
        let capTouched: Bool = dailyCap != origCap || boxIds != origBoxes
        if dailyCap < 1 || (capTouched && !mail.boxes.isEmpty && dailyCap > capMax) { out.append(String(localized: "писем в день — от 1 до \(capMax)")) }
        if windowFrom >= windowTo { out.append(String(localized: "окно отправки: начало раньше конца")) }
        return out
    }

    private var stepsPayload: [[String: Any]] {
        var out: [[String: Any]] = []
        for (i, s) in steps.enumerated() {
            let subject: String = s.subject.trimmingCharacters(in: .whitespacesAndNewlines)
            let delay: Int = i == 0 ? 0 : s.delayDays
            out.append(["subject": subject, "body": s.body, "delayDays": delay])
        }
        return out
    }

    /// только изменённые поля
    private var patch: [String: Any] {
        var b: [String: Any] = [:]
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n != c.name { b["name"] = n }
        let original: [StepDraft] = Self.drafts(c, withSent: false)
        var stepsChanged: Bool = original.count != steps.count
        if !stepsChanged {
            for i in original.indices {
                let was: StepDraft = original[i]
                let now: StepDraft = steps[i]
                if was.subject != now.subject.trimmingCharacters(in: .whitespacesAndNewlines) || was.body != now.body || was.delayDays != now.delayDays { stepsChanged = true }
            }
        }
        if stepsChanged { b["steps"] = stepsPayload }
        if boxIds != origBoxes { b["boxIds"] = boxIds.sorted() }
        if dailyCap != origCap { b["dailyCap"] = dailyCap }
        if windowFrom != (c.windowFrom ?? 10) || windowTo != (c.windowTo ?? 19) { b["windowFrom"] = windowFrom; b["windowTo"] = windowTo }
        if weekdaysOnly != (c.weekdaysOnly ?? true) { b["weekdaysOnly"] = weekdaysOnly }
        return b
    }

    private var changed: Bool { ready && !patch.isEmpty }
    private var canSave: Bool { changed && problems.isEmpty && !saving && (store.fixture || NetMonitor.shared.online) }

    private func save() {
        guard canSave else { return }
        let body: [String: Any] = patch
        serverError = nil
        if store.fixture { store.show(String(localized: "настройки рассылки сохранены")); dismiss(); return }
        saving = true
        Task {
            do {
                try await mail.editCampaign(c.id, body)
                saving = false
                store.show(String(localized: "настройки рассылки сохранены"))
                dismiss()
            } catch {
                saving = false
                serverError = friendly(error)
            }
        }
    }
}

/// Редактор одного письма цепочки: тема, текст, пауза в днях.
struct StepEditorView: View {
    @Binding var step: StepDraft
    let index: Int
    @FocusState private var focus: Field?
    enum Field { case subject, body }

    private var subjectPrompt: LocalizedStringKey {
        index == 0 ? "тема письма" : "тема (можно пусто — уйдёт ответом в той же переписке)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if step.sent > 0 {
                    Label("Уже отправлено: \(step.sent). Новый текст получат только те, кому это письмо ещё не уходило.", systemImage: "info.circle")
                        .font(Typo.body(13)).foregroundStyle(Pal.fg2).padding(.horizontal, 4).padding(.top, 8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if index > 0 {
                    Cap(String(localized: "пауза"))
                    GroupRow(first: true) {
                        Stepper(value: $step.delayDays, in: CampaignLimits.delay) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("через \(step.delayDays) дн. после прошлого письма")
                                Text("если компания не ответила; от 1 до 30 дней").font(Typo.body(13)).foregroundStyle(Pal.fg2)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .glassRect(24)
                }
                Cap(String(localized: "тема"))
                TextField(subjectPrompt, text: $step.subject, axis: .vertical)
                    .focused($focus, equals: .subject)
                    .font(Typo.body(16))
                    .foregroundStyle(Pal.ink)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(minHeight: 48)
                    .glassRect(24)
                Text("\(step.subject.count) / \(CampaignLimits.subject)").font(Typo.mono(12)).foregroundStyle(step.subject.count > CampaignLimits.subject ? Pal.danger : Pal.fg3)
                    .padding(.horizontal, 4).padding(.top, 4)
                Cap(String(localized: "текст"))
                TextEditor(text: $step.body)
                    .focused($focus, equals: .body)
                    .font(Typo.body(16))
                    .foregroundStyle(Pal.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 260)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .glassRect(24)
                    .accessibilityLabel(Text("текст письма"))
                Text("\(step.body.count) / \(CampaignLimits.body)").font(Typo.mono(12)).foregroundStyle(step.body.count > CampaignLimits.body ? Pal.danger : Pal.fg3)
                    .padding(.horizontal, 4).padding(.top, 4)
            }
            .padding(.horizontal, 16).padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(MetalBackground(star: .none).ignoresSafeArea())
        .navigationTitle(Text("письмо \(index + 1)"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("готово") { focus = nil }
            }
        }
    }
}

struct ThreadView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let id: Int
    let mail: MailStore
    let boxes: [MailBox]
    @State private var msgs: [ThreadMsg] = []
    @State private var loaded = false
    @State private var text = ""
    @State private var sending = false
    @FocusState private var focus: Bool
    /// переводы входящих: id письма → перевод и язык оригинала
    @State private var tr: [Int: MailTranslation] = [:]
    /// письма, которые сейчас переводятся («переводим…»)
    @State private var trBusy: Set<Int> = []
    /// не перевелось: id письма → причина (с кнопкой «повторить»)
    @State private var trFailed: [Int: String] = [:]
    @State private var showOriginal: Set<Int> = []
    /// переводить ответ на язык собеседника при отправке
    @State private var translateOut = true
    @State private var hintShown = false
    /// в переписке есть входящие не на языке интерфейса (для плашки «перевод выключен» и вопроса перед отправкой)
    @State private var foreign = false
    /// алерт согласия на перевод через ИИ: для входящих / перед отправкой ответа
    @State private var askAIIncoming = false
    @State private var askAIReply = false
    /// в этой переписке выбрали «отправить без перевода» — больше не спрашиваем
    @State private var sendAsIs = false

    /// язык собеседника — по последнему переведённому входящему письму
    private var partnerLang: String? {
        for m in msgs.reversed() where !m.mine { if let f = tr[m.id]?.from, f != MailLang.mine, f != "?" { return f } }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(msgs.last?.subject ?? String(localized: "письмо")).font(Typo.display(17)).foregroundStyle(Pal.ink).lineLimit(2)
                Spacer()
                if let lang = partnerLang {
                    // значок языка собеседника: тап — включить/выключить перевод ответа
                    Button {
                        haptic()
                        withAnimation { translateOut.toggle() }
                        store.show(translateOut ? String(localized: "ответ переведём на \(MailLang.acc(lang))") : String(localized: "перевод ответа выключен — уйдёт как написано"))
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "globe").iconFont(10, .semibold)
                            Text(String(lang.prefix(2)).uppercased()).font(Typo.body(13, .semibold))
                        }
                        .foregroundStyle(translateOut ? Pal.onInk : Pal.ink)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(translateOut ? Pal.ink : Pal.ink.opacity(0.08)))
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel(Text("перевод переписки"))
                }
                CircleButton(system: "xmark", size: 36, iconSize: 13) { dismiss() }
            }
            .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 8)
            if foreign && !store.aiConsent { aiOffBanner }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 10) {
                        if !loaded && msgs.isEmpty { threadSkeleton }
                        ForEach(msgs) { m in bubble(m).id(m.id) }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: msgs.count) { _, _ in
                    updateForeign()
                    if let l = msgs.last { withAnimation { proxy.scrollTo(l.id, anchor: .bottom) } }
                }
            }
            if focus, let lang = partnerLang, let last = msgs.last, replyBox(last) != nil {
                HStack {
                    Button { haptic(); withAnimation { translateOut.toggle() } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "globe").iconFont(11, .semibold)
                            Text(translateOut ? "\(MailLang.mine.uppercased()) → \(String(lang.prefix(2)).uppercased())" : "без перевода").font(Typo.body(13, .semibold))
                            Image(systemName: translateOut ? "checkmark.circle.fill" : "circle").iconFont(13)
                        }
                        .foregroundStyle(Pal.ink)
                        .padding(.horizontal, 10).frame(minHeight: 26)
                        .background(Capsule().fill(Pal.surface.opacity(0.7)))
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.top, 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let last = msgs.last, replyBox(last) != nil {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("", text: $text, prompt: Text("ответ").foregroundColor(Pal.fg3), axis: .vertical)
                        .lineLimit(1...6).font(Typo.body(15)).foregroundStyle(Pal.ink).focused($focus)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Pal.surface.opacity(0.8)))
                    Button(action: send) {
                        Image(systemName: sending ? "ellipsis" : "arrow.up").iconFont(16, .bold).foregroundStyle(Pal.onInk)
                            .frame(width: 44, height: 44).background(Circle().fill(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Pal.ink.opacity(0.3) : Pal.ink))
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel(Text("отправить ответ"))
                    .disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
        }
        .background(MetalBackground(star: .none).ignoresSafeArea())
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: focus)
        .overlay {
            if hintShown, let lang = partnerLang {
                TranslateHint(langName: MailLang.acc(lang)) { withAnimation { hintShown = false } }
            }
        }
        .onChange(of: partnerLang) { _, l in
            // один раз при первом входе в иностранную переписку
            if l != nil && !UserDefaults.standard.bool(forKey: "trHintSeen") {
                UserDefaults.standard.set(true, forKey: "trHintSeen")
                withAnimation(.spring(response: 0.4)) { hintShown = true }
            }
        }
        .presentationDragIndicator(.visible)
        .task { await openThread() }
        .onChange(of: store.aiConsent) { _, on in aiConsentChanged(on) }
        .alert(Text("Перевод писем через ИИ"), isPresented: $askAIIncoming) {
            Button("Разрешить") { allowAI(thenSend: false) }
            Button("Не сейчас", role: .cancel) {}
        } message: {
            Text("Для перевода текст писем отправляется в сторонние ИИ-сервисы (Groq). Разрешить?")
        }
        .alert(Text("Перевод писем через ИИ"), isPresented: $askAIReply) {
            Button("Разрешить") { allowAI(thenSend: true) }
            Button("Отправить без перевода") { sendAsIs = true; send() }
            Button("Не сейчас", role: .cancel) {}
        } message: {
            Text("Для перевода текст писем отправляется в сторонние ИИ-сервисы (Groq). Разрешить?")
        }
    }

    /// плашка над перепиской: перевод через ИИ не разрешён — письма в оригинале
    private var aiOffBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe").iconFont(13, .semibold).foregroundStyle(Pal.fg2)
            Text("Перевод через ИИ выключен").font(Typo.body(13)).foregroundStyle(Pal.fg2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button {
                haptic()
                askAIIncoming = true
            } label: {
                Text("Включить").font(Typo.body(13, .semibold)).foregroundStyle(Pal.ink)
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 14).padding(.trailing, 4)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Pal.ink.opacity(0.06)))
        .padding(.horizontal, 16).padding(.bottom, 6)
        .accessibilityElement(children: .contain)
    }

    /// «Разрешить» в алерте: сохраняем согласие, переводим входящие; если спрашивали перед отправкой — отправляем
    private func allowAI(thenSend: Bool) {
        store.setAIConsent(true)
        Task {
            await translateIncoming()
            if thenSend { send() }
        }
    }

    /// согласие отозвали (настройки) — убираем переводы с экрана; дали — переводим
    private func aiConsentChanged(_ on: Bool) {
        if on {
            Task { await translateIncoming() }
        } else {
            tr = [:]
            trFailed = [:]
            showOriginal = []
        }
    }

    /// есть ли входящие не на языке интерфейса (на телефоне, без отправки куда-либо)
    private func updateForeign() {
        var found: Bool = false
        for m in msgs where !m.mine {
            let main: String = MailText.split(m.body).main
            if needsTranslation(main) && !looksMine(main) { found = true; break }
        }
        foreign = found
    }

    /// язык текста определяем на телефоне (NaturalLanguage): совпадает с языком интерфейса — переводить незачем
    private func looksMine(_ text: String) -> Bool {
        guard let lang: NLLanguage = NLLanguageRecognizer.dominantLanguage(for: text) else { return false }
        let code: String = String(lang.rawValue.prefix(2))
        return code == MailLang.mine
    }

    /// заглушки пузырей, пока переписка грузится впервые
    private var threadSkeleton: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonRows(count: 1, cards: true).padding(.trailing, 60)
            SkeletonRows(count: 1, cards: true).padding(.leading, 60)
        }
        .padding(.top, 12)
    }

    /// копия переписки и переводов — сразу; свежая с сервера — следом, без мигания (одинаковая не перерисовывается)
    private func openThread() async {
        if !store.fixture, let cached = mail.cachedThread(id) {
            msgs = cached
            loaded = true
            updateForeign()
            showCachedTranslations()
        }
        let fresh: [ThreadMsg] = await mail.thread(id, fixture: store.fixture)
        if !fresh.isEmpty && fresh != msgs { msgs = fresh }
        loaded = true
        updateForeign()
        if store.aiConsent {
            await translateIncoming()
        } else if foreign && !UserDefaults.standard.bool(forKey: "aiAskedMail") {
            // один раз сами спрашиваем согласие при первой иностранной переписке; дальше — плашка «Включить»
            UserDefaults.standard.set(true, forKey: "aiAskedMail")
            askAIIncoming = true
        }
    }

    private func showCachedTranslations() {
        guard store.aiConsent else { return }
        let to: String = MailLang.mine
        for m in msgs where !m.mine && tr[m.id] == nil {
            if let t = mail.cachedTranslation(id: m.id, to: to), t.from != to { tr[m.id] = t }
        }
    }

    /// входящие не на языке интерфейса — переводим сами (только «своё» письма, без цитаты)
    private func translateIncoming() async {
        guard store.aiConsent else { return }
        for m in msgs where !m.mine && tr[m.id] == nil {
            let main: String = MailText.split(m.body).main
            guard needsTranslation(main) else { continue }
            await translateOne(m.id, main)
        }
    }

    /// интерфейс по-русски — русские письма не отправляем на перевод; на других языках сервер сам скажет язык оригинала
    private func needsTranslation(_ main: String) -> Bool {
        if main.isEmpty { return false }
        return !(MailLang.mine == "ru" && MailLang.looksRussian(main))
    }

    /// перевести одно письмо: «переводим…», 2 попытки внутри MailStore, при ошибке — причина и «повторить»
    private func translateOne(_ msgId: Int, _ text: String) async {
        let to: String = MailLang.mine
        guard store.aiConsent else { return }
        if trBusy.contains(msgId) { return }
        trFailed[msgId] = nil
        trBusy.insert(msgId)
        do {
            let t: MailTranslation = try await mail.translateMessage(id: msgId, text: text, to: to, fixture: store.fixture)
            trBusy.remove(msgId)
            if t.from != to {
                withAnimation(.easeInOut(duration: 0.2)) { tr[msgId] = t }
            }
        } catch {
            trBusy.remove(msgId)
            if error is CancellationError { return }
            trFailed[msgId] = friendly(error)
        }
    }

    private func retryTranslate(_ m: ThreadMsg) {
        haptic()
        if !store.aiConsent { askAIIncoming = true; return }
        let main: String = MailText.split(m.body).main
        Task { await translateOne(m.id, main) }
    }

    /// под письмом: «переводим…» или «не удалось перевести · повторить»
    @ViewBuilder private func trStatus(_ m: ThreadMsg) -> some View {
        if let why = trFailed[m.id] {
            VStack(alignment: .leading, spacing: 4) {
                Text("не удалось перевести: \(why)").font(Typo.body(13)).foregroundStyle(Pal.danger)
                    .fixedSize(horizontal: false, vertical: true)
                Button { retryTranslate(m) } label: {
                    Label("повторить перевод", systemImage: "arrow.clockwise")
                        .font(Typo.body(13, .semibold)).foregroundStyle(Pal.ink)
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .background(Capsule().fill(Pal.ink.opacity(0.08)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        } else if trBusy.contains(m.id) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("переводим…").font(Typo.body(13, .semibold)).foregroundStyle(Pal.fg2)
            }
            .accessibilityElement(children: .combine)
        }
    }

    @State private var showQuote: Set<Int> = []

    private func bubble(_ m: ThreadMsg) -> some View {
        let parts = MailText.split(m.body)
        // свои письма — справа, как в мессенджере; чужие — слева
        return HStack(spacing: 0) {
            if m.mine { Spacer(minLength: 44) }
            bubbleBody(m, parts)
            if !m.mine { Spacer(minLength: 44) }
        }
    }

    private func bubbleBody(_ m: ThreadMsg, _ parts: (main: String, quote: String)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(author(m)).font(Typo.body(13, .semibold)).lineLimit(1)
                Text(MailDate.long(m.date)).font(Typo.mono(12, .medium)).foregroundStyle(Pal.fg3)
            }
            if let t = tr[m.id], !showOriginal.contains(m.id) {
                Text(t.text).font(Typo.body(16)).lineSpacing(3).textSelection(.enabled)
            } else {
                Text(parts.main).font(Typo.body(16)).lineSpacing(3).textSelection(.enabled)
            }
            trStatus(m)
            if let t = tr[m.id] {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { if showOriginal.contains(m.id) { showOriginal.remove(m.id) } else { showOriginal.insert(m.id) } }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "globe").iconFont(11, .semibold)
                        Text(showOriginal.contains(m.id) ? "показать перевод" : "переведено с \(MailLang.gen(t.from)) · оригинал")
                    }
                    .font(Typo.body(13, .semibold)).foregroundStyle(Pal.fg2)
                }
                .buttonStyle(.plain)
            }
            if !parts.quote.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { if showQuote.contains(m.id) { showQuote.remove(m.id) } else { showQuote.insert(m.id) } }
                } label: {
                    Text(showQuote.contains(m.id) ? "скрыть цитату" : "• • •  предыдущая переписка").font(Typo.body(13, .semibold)).foregroundStyle(Pal.fg2)
                        .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(Pal.ink.opacity(0.06)))
                }
                .buttonStyle(.plain)
                if showQuote.contains(m.id) {
                    Text(parts.quote).font(Typo.body(13)).foregroundStyle(Pal.fg2).lineSpacing(2).textSelection(.enabled)
                        .padding(.leading, 10).overlay(alignment: .leading) { Rectangle().fill(Pal.ink.opacity(0.15)).frame(width: 2) }
                }
            }
        }
        .foregroundStyle(Pal.ink)
        .padding(14)
        .background(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: m.mine ? 20 : 6, bottomTrailingRadius: m.mine ? 6 : 20, topTrailingRadius: 20, style: .continuous)
            .fill(m.mine ? Color(light: 0xDDE8E0, dark: 0x2F4A3B) : Pal.surface.opacity(0.85)))
        .fixedSize(horizontal: false, vertical: true)
    }

    /// подпись пузыря: «вы» / имя отправителя / адрес (раньше — вложенный тернарник с ?? прямо в Text)
    private func author(_ m: ThreadMsg) -> String {
        if m.mine { return String(localized: "вы") }
        if let n = m.fromName, !n.isEmpty { return n }
        return m.fromAddr
    }

    /// с какого ящика отвечать: тот, в котором лежит письмо (или первый)
    private func replyBox(_ m: ThreadMsg) -> Int? { m.mailboxId ?? boxes.first?.id }

    private func send() {
        guard let last = msgs.last, let box = replyBox(last) else { return }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        // отвечаем собеседнику: на входящее — отправителю, на своё — получателю
        let to = last.mine ? (last.toAddr ?? "") : last.fromAddr
        let subject = last.subject.lowercased().hasPrefix("re:") ? last.subject : "Re: " + last.subject
        if store.fixture { store.show(String(localized: "письмо отправлено")); text = ""; return }
        // иностранная переписка без согласия на ИИ: спрашиваем — разрешить перевод или отправить как написано
        if !store.aiConsent && !sendAsIs && (foreign || partnerLang != nil) {
            askAIReply = true
            return
        }
        let useTranslation: Bool = translateOut && store.aiConsent
        sending = true
        Task {
            do {
                var out = body
                var note: String = String(localized: "письмо отправлено")
                if useTranslation, let lang = partnerLang {
                    // перевод ответа (2 попытки внутри); не вышло — письмо не уходит, текст остаётся в поле
                    do {
                        out = try await mail.translate(body, to: lang, fixture: false).text
                    } catch {
                        store.show(String(localized: "ответ не перевёлся: \(friendly(error)). Нажмите «отправить» ещё раз или выключите перевод"), ok: false, long: true)
                        sending = false
                        return
                    }
                    note = String(localized: "отправлено на \(MailLang.acc(lang))")
                }
                // вся цепочка Message-ID по порядку (корень первым) — иначе ответ уходит в другую ветку и не виден тут
                var refs: [String] = []
                for m in msgs { if let mid = m.messageId, !mid.isEmpty, !refs.contains(mid) { refs.append(mid) } }
                try await mail.send(box: box, to: to, subject: subject, text: out, replyTo: msgs.last(where: { $0.messageId?.isEmpty == false })?.messageId, references: refs.joined(separator: " "))
                text = ""; focus = false
                store.show(note)
                // свой ответ сразу в переписке (то, что реально ушло), потом перечитываем тред с сервера
                let mine = ThreadMsg(id: -Int(Date().timeIntervalSince1970), mailboxId: box, folder: "sent", messageId: nil, fromAddr: "", fromName: nil,
                                     toAddr: to, subject: subject, body: out, date: ISO8601DateFormatter().string(from: Date()))
                withAnimation(.spring(response: 0.3)) { msgs.append(mine) }
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                let fresh = await mail.thread(id, fixture: false)
                // сервер мог ещё не положить ответ в цепочку — тогда оставляем локальный пузырь
                if fresh.count >= msgs.count { msgs = fresh }
            } catch { store.show((error as? APIError)?.message ?? String(localized: "не отправилось"), ok: false) }
            sending = false
        }
    }
}


/// Текст письма без цитаты: всё после «… написал(а):», «On … wrote:», строк с «>», «-----Original Message-----»,
/// блока «От: … Отправлено: …» и подписи «-- » уходит в quote (показывается по кнопке).
enum MailText {
    private static let cutRes: [NSRegularExpression] = [
        #"^\s*>"#,
        #"^\s*-{2,}\s*(original message|исходное сообщение|forwarded message|пересылаемое сообщение|пересланное сообщение)"#,
        #"^\s*(on|am|le|el)\s.+(wrote|schrieb|a écrit|escribió)\s*:\s*$"#,
        #".+(написал|написала|пишет|писал|писала)\s*(\(а\))?\s*:\s*$"#,
        #"^.{0,80}<[^>\s]+@[^>\s]+>\s*:\s*$"#,
        #"^\s*(от|from)\s*:\s*.+@"#,
        #"^\s*_{8,}\s*$"#,
        #"^--\s*$"#,
        #"^\s*(отправлено с|sent from my|отправлено из)\s"#,
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    static func split(_ body: String) -> (main: String, quote: String) {
        let text = body.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = text.components(separatedBy: "\n")
        var cut: Int?
        for (i, line) in lines.enumerated() where i > 0 || lines.count == 1 {
            let r = NSRange(line.startIndex..., in: line)
            if cutRes.contains(where: { $0.firstMatch(in: line, range: r) != nil }) { cut = i; break }
        }
        guard let c = cut else { return (text.trimmingCharacters(in: .whitespacesAndNewlines), "") }
        let main = lines[..<c].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let quote = lines[c...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        // если «своего» текста не осталось — показываем всё как есть
        return main.isEmpty ? (text.trimmingCharacters(in: .whitespacesAndNewlines), "") : (main, quote)
    }
}

/// Новое письмо: с какого ящика, кому, тема, текст.
struct ComposeView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let mail: MailStore
    let boxes: [MailBox]
    var preferBox: Int?
    @State private var from: Int?
    @State private var to = ""
    @State private var subject = ""
    @State private var text = ""
    @State private var sending = false
    @State private var confirmClose = false
    @FocusState private var focus: Field?
    enum Field { case to, subject, text }

    private var valid: Bool {
        let t = to.trimmingCharacters(in: .whitespaces)
        return t.contains("@") && t.contains(".") && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && from != nil
    }
    private var dirty: Bool { !to.isEmpty || !subject.isEmpty || !text.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("отмена") { if dirty { confirmClose = true } else { dismiss() } }
                    .font(Typo.body(16)).foregroundStyle(Pal.ink)
                Spacer()
                Text("новое письмо").font(Typo.display(16)).foregroundStyle(Pal.ink)
                Spacer()
                Button(action: send) {
                    Image(systemName: sending ? "ellipsis" : "arrow.up").iconFont(15, .bold).foregroundStyle(Pal.onInk)
                        .frame(width: 40, height: 40).background(Circle().fill(valid ? Pal.ink : Pal.ink.opacity(0.3)))
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle()).disabled(!valid || sending)
                .accessibilityLabel(Text("отправить письмо"))
                .accessibilityHint(Text(valid ? "" : "укажите адрес и текст письма"))
            }
            .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 10)
            VStack(spacing: 0) {
                GroupRow(first: true) {
                    Text("от").foregroundStyle(Pal.fg2).frame(width: 44, alignment: .leading)
                    Menu {
                        ForEach(boxes) { b in Button(b.address) { from = b.id } }
                    } label: {
                        HStack(spacing: 4) {
                            Text(boxes.first { $0.id == from }?.address ?? String(localized: "выбрать почту")).lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down").iconFont(10, .semibold).opacity(0.5)
                        }
                        .foregroundStyle(Pal.ink)
                    }
                    Spacer()
                }
                GroupRow {
                    Text("кому").foregroundStyle(Pal.fg2).frame(width: 44, alignment: .leading)
                    TextField("", text: $to, prompt: Text("адрес@домен.ru").foregroundColor(Pal.fg3))
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focus, equals: .to).submitLabel(.next).onSubmit { focus = .subject }
                }
                GroupRow {
                    Text("тема").foregroundStyle(Pal.fg2).frame(width: 44, alignment: .leading)
                    TextField("", text: $subject).focused($focus, equals: .subject).submitLabel(.next).onSubmit { focus = .text }
                }
            }
            .glassRect(20)
            .padding(.horizontal, 12)
            TextField("", text: $text, prompt: Text("текст письма").foregroundColor(Pal.fg3), axis: .vertical)
                .font(Typo.body(16)).foregroundStyle(Pal.ink).lineLimit(8...30)
                .focused($focus, equals: .text)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Pal.surface.opacity(0.7)))
                .padding(12)
            Spacer(minLength: 0)
        }
        .background(MetalBackground(star: .none).ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(dirty)
        .onAppear {
            from = preferBox ?? boxes.first?.id
            focus = .to
        }
        .confirmationDialog("Удалить черновик?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("удалить", role: .destructive) { dismiss() }
            Button("продолжить писать", role: .cancel) {}
        }
    }

    private func send() {
        guard let box = from, valid else { return }
        if store.fixture { store.show(String(localized: "письмо отправлено")); dismiss(); return }
        sending = true
        Task {
            do {
                try await mail.send(box: box, to: to.trimmingCharacters(in: .whitespaces), subject: subject, text: text, replyTo: nil)
                store.show(String(localized: "письмо отправлено"))
                dismiss()
            } catch { store.show((error as? APIError)?.message ?? String(localized: "не отправилось"), ok: false) }
            sending = false
        }
    }
}


/// Языки для подписей перевода. Интерфейс по-русски — названия с падежом из словаря ниже,
/// на других языках — системное название языка («Spanish», «Spanisch»…).
enum MailLang {
    /// язык интерфейса (ru, en, de…): на него переводим входящие письма, с него — ответы
    static var mine: String { String((Bundle.main.preferredLocalizations.first ?? "en").prefix(2)) }
    static let names: [String: (acc: String, gen: String)] = [
        "en": ("английский", "английского"), "es": ("испанский", "испанского"), "de": ("немецкий", "немецкого"),
        "fr": ("французский", "французского"), "it": ("итальянский", "итальянского"), "pt": ("португальский", "португальского"),
        "pl": ("польский", "польского"), "tr": ("турецкий", "турецкого"), "uk": ("украинский", "украинского"),
        "nl": ("нидерландский", "нидерландского"), "cs": ("чешский", "чешского"), "ro": ("румынский", "румынского"),
        "ka": ("грузинский", "грузинского"), "kk": ("казахский", "казахского"), "ar": ("арабский", "арабского"), "zh": ("китайский", "китайского"),
    ]
    static func acc(_ c: String) -> String {
        let code: String = String(c.prefix(2))
        if mine == "ru" { return names[code]?.acc ?? String(localized: "язык собеседника") }
        return Locale(identifier: mine).localizedString(forLanguageCode: code) ?? String(localized: "язык собеседника")
    }
    static func gen(_ c: String) -> String {
        let code: String = String(c.prefix(2))
        if mine == "ru" { return names[code]?.gen ?? String(localized: "другого языка") }
        return Locale(identifier: mine).localizedString(forLanguageCode: code) ?? String(localized: "другого языка")
    }
    /// «на испанском»
    static func prep(_ c: String) -> String {
        let g = gen(c)
        return g.hasSuffix("ого") ? String(g.dropLast(3)) + "ом" : g
    }
    static func looksRussian(_ t: String) -> Bool {
        let cyr = t.unicodeScalars.filter { (0x0400...0x04FF).contains($0.value) }.count
        let lat = t.unicodeScalars.filter { ($0.value >= 65 && $0.value <= 90) || ($0.value >= 97 && $0.value <= 122) }.count
        return cyr > 0 && cyr >= lat * 2
    }
}


/// Подсказка один раз: пишите по-русски — переведём.
struct TranslateHint: View {
    let langName: String
    let done: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea().onTapGesture(perform: done)
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "globe").iconFont(26, .semibold).foregroundStyle(Pal.ink)
                Text("Пишите по-русски").font(Typo.display(20)).foregroundStyle(Pal.ink)
                Text("Письма собеседника переводятся на русский, а ваш ответ уйдёт на \(langName) автоматически. Оригинал всегда можно открыть, перевод — выключить значком языка в шапке письма.")
                    .font(Typo.body(15)).foregroundStyle(Pal.fg2).lineSpacing(3)
                Button(action: done) {
                    Text("понятно").font(Typo.body(16, .semibold)).frame(maxWidth: .infinity).frame(minHeight: 48).primaryFill(16)
                }
                .buttonStyle(PressStyle())
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Pal.surface.opacity(0.97)))
            .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }
}
