import Foundation

/// Язык данных для снимков CI (-fixture): интерфейс по-английски → английские компании, поводы и письма; иначе русские.
/// Вне `#if DEBUG`: им пользуются и данные снимков в MailStore/Store (они есть в Release-коде).
enum FixtureText {
    static var english: Bool {
        let first: String = Locale.preferredLanguages.first ?? ""
        if first.hasPrefix("en") { return true }
        let loc: String = Bundle.main.preferredLocalizations.first ?? ""
        return loc == "en"
    }
    static func pick(_ ru: String, _ en: String) -> String { english ? en : ru }
}

#if DEBUG
@MainActor
enum Fixture {
    static func apply(_ store: Store) {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-login") {
            store.phase = .login
            return
        }
        store.phase = .ready
        // подсказка «Пишите по-…» в переписке: в снимках всегда одинаково (не зависит от прошлых запусков); -nohints — чистая переписка
        UserDefaults.standard.set(args.contains("-nohints"), forKey: "trHintSeen")
        let en: Bool = FixtureText.english
        store.user = User(id: 1, email: "demo@example.com", name: nil, role: "owner")
        store.overview.planName = en ? "Business" : "Бизнес"
        store.overview.metrics.issued = 12
        store.overview.metrics.wrote = 5
        store.overview.metrics.answered = 2
        let fmt: ISO8601DateFormatter = ISO8601DateFormatter()
        let date: String = fmt.string(from: .now)
        store.segments = en ? englishSegments() : russianSegments()
        store.leads = en ? englishLeads(date) : russianLeads(date)
        if en {
            store.managers = [Manager(id: 1, name: "Anna", email: "anna@example.com", joined: true), Manager(id: 2, name: "Oliver", email: "oliver@example.com", joined: false)]
        } else {
            store.managers = [Manager(id: 1, name: "Анна", email: "anna@example.com", joined: true), Manager(id: 2, name: "Олег", email: "oleg@example.com", joined: false)]
        }
        store.overview.limits = Limits(leads: 300, leadsUsed: 112, segments: 3, segmentsOn: 1, periodEnd: nil, daysLeft: 18)
        store.leadsTotal = store.leads.count
        store.bulkManagers = store.managers
        store.mailState = .ok
        store.bulkOptionsLoaded = true
        store.signals = en ? englishSignals(fmt) : russianSignals(fmt)
        if let screenIndex = args.firstIndex(of: "-screen"), args.indices.contains(screenIndex + 1) {
            switch args[screenIndex + 1] {
            case "leads": store.tab = .leads
            case "lead": store.tab = .leads; store.leadsPath = [.lead(1)]
            case "mail": store.tab = .mail
            case "thread": store.tab = .mail; store.fixtureMail = "thread"
            case "compose": store.tab = .mail; store.fixtureMail = "compose"
            case "lead3": store.tab = .leads; store.leadsPath = [.lead(3)]
            case "folders": store.tab = .leads; store.fixtureMail = "folders"
            case "signals": store.tab = .signals
            case "settings": store.tab = .settings
            case "collect": store.homePath = [.collect]
            case "home-select": store.segSelecting = true; store.segSelected = [2]
            case "leads-select": store.tab = .leads; store.leadFilter = "all"; store.leadSelecting = true; store.leadSelected = [1, 3, 4]
            case "leads-mail": store.tab = .leads; store.leadFilter = "all"; store.leadSelecting = true; store.leadSelected = [1, 3, 4]; store.fixtureMail = "leads-mail"; store.leadMailSheet = true
            case "leads-sguardo": store.tab = .leads; store.leadFilter = "all"; store.leadSelecting = true; store.leadSelected = [1, 3, 4]; store.fixtureMail = "leads-sguardo"; store.leadSguardoSheet = true
            case "leads-sguardo-none": store.tab = .leads; store.leadFilter = "all"; store.leadSelecting = true; store.leadSelected = [1, 3, 4]; store.fixtureMail = "leads-sguardo-none"; store.leadSguardoSheet = true
            case "leads-delete": store.tab = .leads; store.leadFilter = "all"; store.leadSelecting = true; store.leadSelected = [1, 3]; store.leadConfirmDelete = true
            case "home-delete": store.segSelecting = true; store.segSelected = [2, 3]; store.segConfirmDelete = true
            // UX 11.11 (снимки 30–39): фильтр, пустой список, рассылки, настройки ниже
            case "leads-filter": store.tab = .leads; store.fixtureMail = "filter"
            case "leads-empty": store.tab = .leads; store.leads = []; store.leadsTotal = 0
            case "camp-settings": store.tab = .mail; store.fixtureMail = "camp-settings"
            case "camp-delete": store.tab = .mail; store.fixtureMail = "camp-delete"
            case "settings-more": store.tab = .settings; store.fixtureMail = "settings-more"
            // финал 11.11 (снимки 22–23): папки с сервера, редактор письма цепочки
            case "folders-server": store.tab = .leads; store.leadFilter = "all"; store.fixtureMail = "folders-server"
            case "camp-step": store.tab = .mail; store.fixtureMail = "camp-step"
            case "account-delete": store.tab = .settings; store.fixtureMail = "account-delete"
            default: break
            }
        }
    }

    // MARK: - русские данные

    private static func russianSegments() -> [Segment] {
        return [
            Segment(id: 1, city: "Казань", niche: "Кофейни", on: true, left: 18, found: 30, limit: 30, issued: 12, exhausted: false, mismatch: nil),
            Segment(id: 2, city: "london, united kingdom", niche: "auto repair shops", on: false, left: 40, found: 60, limit: nil, issued: 20, exhausted: false, mismatch: nil),
            Segment(id: 3, city: "Санкт-Петербург", niche: "Стоматологические клиники", on: true, left: 0, found: 25, limit: 25, issued: 25, exhausted: true, mismatch: nil)
        ]
    }

    private static func russianLeads(_ date: String) -> [Lead] {
        var list: [Lead] = []
        list.append(Lead(id: 1, name: "Кофейня «Маяк»", city: "Казань", niche: "Кофейни",
                         site: "https://example.com", email: "hello@example.com", tg: nil, wa: nil, phone: nil,
                         message: "Здравствуйте! Заметил, что на вашем сайте сложно найти меню с телефона.",
                         note: nil, score: 80, status: "new", at: date, claim: nil,
                         whatsWrong: "Меню сложно найти на телефоне", rating: 4.7, reviews: 34))
        list.append(Lead(id: 2, name: "Зерно", city: "Казань", niche: "Кофейни", site: nil, email: "info@zerno.ru", tg: nil, wa: nil, phone: nil,
                         message: "Здравствуйте!", note: nil, score: 60, status: "written", at: date, claim: nil, whatsWrong: nil, rating: 4.2, reviews: 12))
        list.append(Lead(id: 3, name: "Центр продаж недвижимости", city: "Пермь", niche: "Агентства недвижимости", site: nil, email: nil, tg: nil, wa: nil, phone: "+7 342 000-00-00",
                         message: "Здравствуйте!", note: nil, score: 90, status: "new", at: date, claim: nil, whatsWrong: nil, rating: 4.4, reviews: 23))
        list.append(Lead(id: 4, name: "Кофейня «Утро»", city: "Казань", niche: "Кофейни", site: "https://example.org", email: "utro@example.org", tg: nil, wa: nil, phone: nil,
                         message: "Здравствуйте!", note: nil, score: 70, status: "new", at: date, claim: nil, whatsWrong: nil, rating: 4.5, reviews: 51))
        list.append(Lead(id: 5, name: "Пекарня «Хлебница»", city: "Казань", niche: "Пекарни", site: nil, email: "bread@example.ru", tg: nil, wa: nil, phone: nil,
                         message: "Здравствуйте!", note: nil, score: 50, status: "answered", at: date, claim: nil, whatsWrong: nil, rating: 4.8, reviews: 96))
        return list
    }

    private static func russianSignals(_ fmt: ISO8601DateFormatter) -> [Signal] {
        let now: Date = .now
        return [
            Signal(id: 1, type: "site_down", name: "Кофейня «Маяк»", city: "Казань", at: fmt.string(from: now), detail: nil, power: 8),
            Signal(id: 2, type: "opened", name: "Стоматология «Улыбка»", city: "Санкт-Петербург", at: fmt.string(from: now.addingTimeInterval(-3_600)), detail: nil, power: 7),
            Signal(id: 3, type: "second_point", name: "Зерно", city: "Казань", at: fmt.string(from: now.addingTimeInterval(-7_200)), detail: nil, power: 6),
            Signal(id: 4, type: "moved", name: "Автосервис «Мотор»", city: "Пермь", at: fmt.string(from: now.addingTimeInterval(-14_400)), detail: nil, power: 5),
            Signal(id: 5, type: "vacancy", name: "Пекарня «Хлебница»", city: "Казань", at: fmt.string(from: now.addingTimeInterval(-25_200)), detail: nil, power: 5)
        ]
    }

    // MARK: - английские данные (интерфейс по-английски)

    private static func englishSegments() -> [Segment] {
        return [
            Segment(id: 1, city: "London", niche: "Coffee shops", on: true, left: 18, found: 30, limit: 30, issued: 12, exhausted: false, mismatch: nil),
            Segment(id: 2, city: "Birmingham", niche: "Auto repair shops", on: false, left: 40, found: 60, limit: nil, issued: 20, exhausted: false, mismatch: nil),
            Segment(id: 3, city: "Manchester", niche: "Dental clinics", on: true, left: 0, found: 25, limit: 25, issued: 25, exhausted: true, mismatch: nil)
        ]
    }

    private static func englishLeads(_ date: String) -> [Lead] {
        var list: [Lead] = []
        list.append(Lead(id: 1, name: "The Lighthouse Café", city: "London", niche: "Coffee shops",
                         site: "https://example.com", email: "hello@example.com", tg: nil, wa: nil, phone: nil,
                         message: "Hi! I noticed it's hard to find the menu on your website from a phone.",
                         note: nil, score: 80, status: "new", at: date, claim: nil,
                         whatsWrong: "Menu is hard to find on mobile", rating: 4.7, reviews: 34))
        list.append(Lead(id: 2, name: "Bean & Grind", city: "London", niche: "Coffee shops", site: nil, email: "info@example.net", tg: nil, wa: nil, phone: nil,
                         message: "Hi!", note: nil, score: 60, status: "written", at: date, claim: nil, whatsWrong: nil, rating: 4.2, reviews: 12))
        list.append(Lead(id: 3, name: "Northside Property Sales", city: "Manchester", niche: "Estate agents", site: nil, email: nil, tg: nil, wa: nil, phone: "+44 161 000 0000",
                         message: "Hi!", note: nil, score: 90, status: "new", at: date, claim: nil, whatsWrong: nil, rating: 4.4, reviews: 23))
        list.append(Lead(id: 4, name: "Morning Brew Coffee", city: "London", niche: "Coffee shops", site: "https://example.org", email: "brew@example.org", tg: nil, wa: nil, phone: nil,
                         message: "Hi!", note: nil, score: 70, status: "new", at: date, claim: nil, whatsWrong: nil, rating: 4.5, reviews: 51))
        list.append(Lead(id: 5, name: "Crumb & Co Bakery", city: "London", niche: "Bakeries", site: nil, email: "bake@example.co.uk", tg: nil, wa: nil, phone: nil,
                         message: "Hi!", note: nil, score: 50, status: "answered", at: date, claim: nil, whatsWrong: nil, rating: 4.8, reviews: 96))
        return list
    }

    private static func englishSignals(_ fmt: ISO8601DateFormatter) -> [Signal] {
        let now: Date = .now
        return [
            Signal(id: 1, type: "site_down", name: "The Lighthouse Café", city: "London", at: fmt.string(from: now), detail: nil, power: 8),
            Signal(id: 2, type: "opened", name: "Smile Studio Dental", city: "Manchester", at: fmt.string(from: now.addingTimeInterval(-3_600)), detail: nil, power: 7),
            Signal(id: 3, type: "second_point", name: "Bean & Grind", city: "London", at: fmt.string(from: now.addingTimeInterval(-7_200)), detail: nil, power: 6),
            Signal(id: 4, type: "moved", name: "Kingsway Auto Repair", city: "Birmingham", at: fmt.string(from: now.addingTimeInterval(-14_400)), detail: nil, power: 5),
            Signal(id: 5, type: "vacancy", name: "Crumb & Co Bakery", city: "London", at: fmt.string(from: now.addingTimeInterval(-25_200)), detail: nil, power: 5)
        ]
    }
}
#endif
