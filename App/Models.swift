import Foundation

// Модели — по ответам бэкенда Повода (src/api/routes/cabinet.ts, table.ts). Почти всё необязательное:
// числа из Postgres иногда приходят строкой, поэтому есть гибкое чтение.

extension KeyedDecodingContainer {
    func flexDouble(_ key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Double(s.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }
    func flexInt(_ key: Key) -> Int? {
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        if let d = flexDouble(key) { return Int(d) }
        return nil
    }
    func str(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return String(d) }
        return nil
    }
    func bool(_ key: Key) -> Bool? { try? decodeIfPresent(Bool.self, forKey: key) }
}

struct User: Decodable, Hashable {
    let id: Int?
    let email: String
    let name: String?
    let role: String?
    private enum K: String, CodingKey { case id, email, name, role }
    init(id: Int?, email: String, name: String?, role: String?) { self.id = id; self.email = email; self.name = name; self.role = role }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = c.flexInt(.id); email = c.str(.email) ?? ""; name = c.str(.name); role = c.str(.role)
    }
    var isManager: Bool { role == "manager" }
}

struct MeResponse: Decodable { let user: User }

struct Metrics: Decodable, Hashable {
    var issued = 0, wrote = 0, answered = 0, deals = 0
    private enum K: String, CodingKey { case issued, wrote, answered, deals }
    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        issued = c.flexInt(.issued) ?? 0; wrote = c.flexInt(.wrote) ?? 0; answered = c.flexInt(.answered) ?? 0; deals = c.flexInt(.deals) ?? 0
    }
}

struct Limits: Decodable, Hashable {
    let leads: Int?
    let leadsUsed: Int?
    let segments: Int?
    let segmentsOn: Int?
    let periodEnd: String?
    let daysLeft: Int?
}

struct NextIssue: Decodable, Hashable {
    let when: String?
    let mode: String?
}

struct Overview: Decodable {
    var metrics = Metrics()
    var plan: String?
    var planName: String?
    var limits: Limits?
    var nextIssue: NextIssue?
    var trialUsed: Bool?
    private enum K: String, CodingKey { case metrics, plan, planName, limits, nextIssue, trialUsed }
    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        metrics = (try? c.decode(Metrics.self, forKey: .metrics)) ?? Metrics()
        plan = c.str(.plan); planName = c.str(.planName)
        limits = try? c.decodeIfPresent(Limits.self, forKey: .limits)
        nextIssue = try? c.decodeIfPresent(NextIssue.self, forKey: .nextIssue)
        trialUsed = c.bool(.trialUsed)
    }
}

struct OverviewResponse: Decodable { let overview: Overview }

struct Segment: Decodable, Identifiable, Hashable {
    let id: Int
    let city: String
    let niche: String
    var on: Bool
    let left: Int
    let found: Int
    let limit: Int?
    let issued: Int
    let exhausted: Bool
    let mismatch: String?
    private enum K: String, CodingKey { case id, city, niche, on, left, found, limit, issued, exhausted, mismatch }
    init(id: Int, city: String, niche: String, on: Bool, left: Int, found: Int, limit: Int?, issued: Int, exhausted: Bool, mismatch: String?) {
        self.id = id; self.city = city; self.niche = niche; self.on = on; self.left = left; self.found = found; self.limit = limit; self.issued = issued; self.exhausted = exhausted; self.mismatch = mismatch
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = c.flexInt(.id) ?? 0; city = c.str(.city) ?? ""; niche = c.str(.niche) ?? ""; on = c.bool(.on) ?? false
        left = c.flexInt(.left) ?? 0; found = c.flexInt(.found) ?? 0; limit = c.flexInt(.limit); issued = c.flexInt(.issued) ?? 0
        exhausted = c.bool(.exhausted) ?? false; mismatch = c.str(.mismatch)
    }
}

struct SegmentsResponse: Decodable { let segments: [Segment] }

/// Статусы таблицы лидов (бэкенд): new, written, answered, deal, refused.
enum LeadStatus: String, CaseIterable {
    case new, written, answered, deal, refused
    var title: String {
        switch self {
        case .new: return String(localized: "новый")
        case .written: return String(localized: "связались")
        case .answered: return String(localized: "ответили")
        case .deal: return String(localized: "сделка")
        case .refused: return String(localized: "отказ")
        }
    }
    var order: Int {
        switch self {
        case .new: return 0
        case .answered: return 1
        case .deal: return 2
        case .written: return 3
        case .refused: return 4
        }
    }
}

struct Lead: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let city: String
    let niche: String
    let site: String?
    let email: String?
    let tg: String?
    let wa: String?
    let phone: String?
    var message: String?
    let messageOwn: String?
    let msgLang: String?
    var note: String?
    let score: Double?
    let priority: String?
    var status: String
    let at: String?
    var managerId: Int?
    var manager: String?
    let claim: String?
    let whatsWrong: String?
    let rating: Double?
    let reviews: Int?

    private enum K: String, CodingKey {
        case id, name, city, niche, site, email, tg, wa, phone, message, messageOwn, msgLang, note, score, priority, status, at, managerId, manager, claim, whatsWrong, rating, reviews
    }

    init(id: Int, name: String, city: String, niche: String, site: String?, email: String?, tg: String?, wa: String?, phone: String?, message: String?,
         note: String?, score: Double?, status: String, at: String?, claim: String?, whatsWrong: String?, rating: Double?, reviews: Int?) {
        self.id = id; self.name = name; self.city = city; self.niche = niche; self.site = site; self.email = email; self.tg = tg; self.wa = wa
        self.phone = phone; self.message = message; self.messageOwn = nil; self.msgLang = nil; self.note = note; self.score = score; self.priority = nil
        self.status = status; self.at = at; self.managerId = nil; self.manager = nil; self.claim = claim; self.whatsWrong = whatsWrong; self.rating = rating; self.reviews = reviews
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = c.flexInt(.id) ?? 0
        name = c.str(.name) ?? String(localized: "компания")
        city = c.str(.city) ?? ""
        niche = c.str(.niche) ?? ""
        site = c.str(.site); email = c.str(.email); tg = c.str(.tg); wa = c.str(.wa); phone = c.str(.phone)
        message = c.str(.message); messageOwn = c.str(.messageOwn); msgLang = c.str(.msgLang); note = c.str(.note)
        score = c.flexDouble(.score); priority = c.str(.priority)
        status = c.str(.status) ?? "new"
        at = c.str(.at); managerId = c.flexInt(.managerId); manager = c.str(.manager)
        claim = c.str(.claim); whatsWrong = c.str(.whatsWrong)
        rating = c.flexDouble(.rating); reviews = c.flexInt(.reviews)
    }

    var st: LeadStatus { LeadStatus(rawValue: status) ?? .new }
    var date: Date? { parseISO(at) }
    /// Сила повода 1…10 — из оценки фирмы (score 0…100).
    var power: Int {
        guard let s = score else { return 0 }
        let v = s > 10 ? s / 10 : s
        return max(1, min(10, Int(v.rounded())))
    }
}

struct TableResponse: Decodable {
    let total: Int
    let rows: [Lead]
    private enum K: String, CodingKey { case total, rows }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        rows = (try? c.decode([Lead].self, forKey: .rows)) ?? []
        total = c.flexInt(.total) ?? rows.count
    }
}

struct Signal: Decodable, Identifiable, Hashable {
    let id: Int
    let orgId: Int?
    let type: String
    let text: String?
    let name: String
    let city: String
    let niche: String
    let issued: Bool
    let at: String?
    let detail: String?
    let power: Int?
    private enum K: String, CodingKey { case id, orgId, type, text, name, city, niche, issued, at, payload }
    private struct Payload: Decodable {
        let url: String?; let site: String?; let reason: String?; let p: Double?; let strength: Double?
        private enum PK: String, CodingKey { case url, site, reason, p, strength }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: PK.self)
            url = c.str(.url); site = c.str(.site); reason = c.str(.reason); p = c.flexDouble(.p); strength = c.flexDouble(.strength)
        }
    }
    init(id: Int, type: String, name: String, city: String, at: String?, detail: String?, power: Int?) {
        self.id = id; self.orgId = nil; self.type = type; self.text = nil; self.name = name; self.city = city; self.niche = ""; self.issued = false; self.at = at; self.detail = detail; self.power = power
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = c.flexInt(.id) ?? 0; orgId = c.flexInt(.orgId); type = c.str(.type) ?? ""; text = c.str(.text)
        name = c.str(.name) ?? String(localized: "компания"); city = c.str(.city) ?? ""; niche = c.str(.niche) ?? ""; issued = c.bool(.issued) ?? false; at = c.str(.at)
        let p = try? c.decodeIfPresent(Payload.self, forKey: .payload)
        detail = [p?.url ?? p?.site, p?.reason].compactMap { $0 }.joined(separator: " ")
        let raw = p?.p ?? p?.strength
        power = raw.map { Int($0.rounded()) }
    }
    var date: Date? { parseISO(at) }
}

struct SignalsResponse: Decodable {
    let signals: [Signal]
    let telegram: Bool?
}

struct ContactItem: Decodable, Hashable {
    let kind: String
    let value: String
}

struct SignalOrg: Decodable {
    let name: String?
    let city: String?
    let niche: String?
    let address: String?
    let site: String?
    let maps: String?
}

struct SignalDetail: Decodable {
    let org: SignalOrg?
    let contacts: [ContactItem]
    let message: String?
    let messageOwn: String?
    private enum K: String, CodingKey { case org, contacts, message, messageOwn }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        org = try? c.decodeIfPresent(SignalOrg.self, forKey: .org)
        contacts = (try? c.decodeIfPresent([ContactItem].self, forKey: .contacts)) ?? []
        message = c.str(.message); messageOwn = c.str(.messageOwn)
    }
}

struct TakeResponse: Decodable { let issueId: Int?; let already: Bool? }

struct Manager: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let email: String
    let joined: Bool
    private enum K: String, CodingKey { case id, name, email, joined }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = c.flexInt(.id) ?? 0; name = c.str(.name) ?? String(localized: "менеджер"); email = c.str(.email) ?? ""; joined = c.bool(.joined) ?? false
    }
    init(id: Int, name: String, email: String, joined: Bool) { self.id = id; self.name = name; self.email = email; self.joined = joined }
}

struct ManagersResponse: Decodable { let managers: [Manager] }

struct CollectSeg: Decodable, Identifiable, Hashable {
    let id: Int
    let csId: Int?
    let city: String
    let niche: String
    let state: String
    let active: Bool
    let found: Int
    private enum K: String, CodingKey { case id, csId, city, niche, state, active, found }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = c.flexInt(.id) ?? 0; csId = c.flexInt(.csId); city = c.str(.city) ?? ""; niche = c.str(.niche) ?? ""
        state = c.str(.state) ?? ""; active = c.bool(.active) ?? false; found = c.flexInt(.found) ?? 0
    }
}

struct CollectStatus: Decodable { let segments: [CollectSeg] }

struct CreateSegmentsResponse: Decodable { let ids: [Int]?; let dup: [String]? }

// MARK: - словари

enum Reason {
    static let title: [String: String] = [
        "site_review": String(localized: "есть сайт — стоит посмотреть оформление и запись"), "no_booking": String(localized: "нельзя записаться онлайн"),
        "old_site": String(localized: "устаревший сайт"), "site_dead": String(localized: "сайт не открывается"), "no_site": String(localized: "нет сайта"),
        "social_only": String(localized: "вместо сайта соцсети"), "few_reviews": String(localized: "мало отзывов"), "low_rating": String(localized: "низкий рейтинг"),
        "no_https": String(localized: "нет защищённого соединения"), "no_mobile": String(localized: "сайт не для телефона"), "slow": String(localized: "сайт медленно открывается"),
    ]
    static let short: [String: String] = [
        "site_review": String(localized: "смотреть сайт"), "no_booking": String(localized: "нет записи онлайн"), "old_site": String(localized: "старый сайт"),
        "site_dead": String(localized: "сайт упал"), "no_site": String(localized: "нет сайта"), "social_only": String(localized: "только соцсети"),
        "few_reviews": String(localized: "мало отзывов"), "low_rating": String(localized: "низкий рейтинг"), "no_https": String(localized: "нет https"),
        "no_mobile": String(localized: "не для телефона"), "slow": String(localized: "медленный сайт"),
    ]

    /// Код повода: из бэкенда (claim), иначе — по тому, есть ли сайт.
    static func code(_ l: Lead) -> String {
        if let c = l.claim, !c.isEmpty { return c }
        return (l.site ?? "").isEmpty ? "no_site" : "site_review"
    }
}

enum SignalKind {
    static func info(_ type: String) -> (String, String) {
        switch type {
        case "site_down": return (String(localized: "упал сайт"), String(localized: "сайт не открывается — им срочно нужен новый"))
        case "opened": return (String(localized: "открылись"), String(localized: "новая компания — нужно всё с нуля"))
        case "second_point": return (String(localized: "вторая точка"), String(localized: "расширяются — нужны реклама и люди"))
        case "moved": return (String(localized: "переехали"), String(localized: "новый адрес — обновить сайт и карты"))
        case "vacancy": return (String(localized: "ищут сотрудников"), String(localized: "растут — нужны системы и найм"))
        default: return (type, "")
        }
    }
}

// MARK: - даты

private let isoFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
private let isoPlain: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

func parseISO(_ s: String?) -> Date? {
    guard let s, !s.isEmpty else { return nil }
    return isoFrac.date(from: s) ?? isoPlain.date(from: s)
}

func isoString(_ d: Date) -> String { isoFrac.string(from: d) }

/// Даты и числа — форматтерами текущего языка (не жёсткие русские месяцы и разделители).
enum Fmt {
    static func hm(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }
    static func when(_ d: Date?) -> String {
        guard let d else { return "" }
        let day0 = Calendar.current.startOfDay(for: Date())
        if d >= day0 { return hm(d) }
        if d >= day0.addingTimeInterval(-86400) { return String(localized: "вчера") }
        return d.formatted(.dateTime.day().month(.abbreviated))
    }
    static func num(_ n: Int) -> String { n.formatted(.number) }
    static func rating(_ r: Double) -> String { r.formatted(.number.precision(.fractionLength(1))) }
}

func joinParts(_ parts: [String?]) -> String {
    parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
}
