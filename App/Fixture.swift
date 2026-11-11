#if DEBUG
import Foundation

@MainActor
enum Fixture {
    static func apply(_ store: Store) {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-login") {
            store.phase = .login
            return
        }
        store.phase = .ready
        store.user = User(id: 1, email: "demo@example.com", name: nil, role: "owner")
        store.overview.planName = "Бизнес"
        store.overview.metrics.issued = 12
        store.overview.metrics.wrote = 5
        store.overview.metrics.answered = 2
        let date = ISO8601DateFormatter().string(from: .now)
        store.segments = [
            Segment(id: 1, city: "Казань", niche: "Кофейни", on: true, left: 18, found: 30, limit: 30, issued: 12, exhausted: false, mismatch: nil),
            Segment(id: 2, city: "london, united kingdom", niche: "auto repair shops", on: false, left: 40, found: 60, limit: nil, issued: 20, exhausted: false, mismatch: nil),
            Segment(id: 3, city: "Санкт-Петербург", niche: "Стоматологические клиники", on: true, left: 0, found: 25, limit: 25, issued: 25, exhausted: true, mismatch: nil)
        ]
        store.leads = [
            Lead(id: 1, name: "Кофейня «Маяк»", city: "Казань", niche: "Кофейни",
                 site: "https://example.com", email: "hello@example.com", tg: nil, wa: nil, phone: nil,
                 message: "Здравствуйте! Заметил, что на вашем сайте сложно найти меню с телефона.",
                 note: nil, score: 80, status: "new", at: date, claim: nil,
                 whatsWrong: "Меню сложно найти на телефоне", rating: 4.7, reviews: 34)
        ]
        store.leads.append(Lead(id: 2, name: "Зерно", city: "Казань", niche: "Кофейни", site: nil, email: "info@zerno.ru", tg: nil, wa: nil, phone: nil,
                                message: "Здравствуйте!", note: nil, score: 60, status: "written", at: date, claim: nil, whatsWrong: nil, rating: 4.2, reviews: 12))
        store.leads.append(Lead(id: 3, name: "Центр продаж недвижимости", city: "Пермь", niche: "Агентства недвижимости", site: nil, email: nil, tg: nil, wa: nil, phone: "+7 342 000-00-00",
                                message: "Здравствуйте!", note: nil, score: 90, status: "new", at: date, claim: nil, whatsWrong: nil, rating: 4.4, reviews: 23))
        store.leads.append(Lead(id: 4, name: "Кофейня «Утро»", city: "Казань", niche: "Кофейни", site: "https://example.org", email: "utro@example.org", tg: nil, wa: nil, phone: nil,
                                message: "Здравствуйте!", note: nil, score: 70, status: "new", at: date, claim: nil, whatsWrong: nil, rating: 4.5, reviews: 51))
        store.leads.append(Lead(id: 5, name: "Пекарня «Хлебница»", city: "Казань", niche: "Пекарни", site: nil, email: "bread@example.ru", tg: nil, wa: nil, phone: nil,
                                message: "Здравствуйте!", note: nil, score: 50, status: "answered", at: date, claim: nil, whatsWrong: nil, rating: 4.8, reviews: 96))
        store.managers = [Manager(id: 1, name: "Анна", email: "anna@example.com", joined: true), Manager(id: 2, name: "Олег", email: "oleg@example.com", joined: false)]
        store.overview.limits = Limits(leads: 300, leadsUsed: 112, segments: 3, segmentsOn: 1, periodEnd: nil, daysLeft: 18)
        store.leadsTotal = store.leads.count
        store.bulkManagers = store.managers
        store.mailState = .ok
        store.bulkOptionsLoaded = true
        store.signals = [Signal(id: 1, type: "site_down", name: "Кофейня «Маяк»", city: "Казань", at: date, detail: nil, power: 8)]
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
}
#endif
