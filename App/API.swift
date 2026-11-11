import Foundation

/// Кабинет Повода: https://disify.dev/povod (Vercel-прокси на бэкенд). Адреса — со слэшем на конце (иначе 308).
/// Сессия — cookie бэкенда в общем HTTPCookieStorage; к чужим хостам она не уходит.
enum API {
    static let origin = URL(string: "https://disify.dev")!
    static let basePath = "/povod"
    static let site = URL(string: "https://disify.dev/povod/")!

    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpCookieStorage = HTTPCookieStorage.shared
        c.httpCookieAcceptPolicy = .always
        c.httpShouldSetCookies = true
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = 60
        return URLSession(configuration: c)
    }()

    static func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        var p = path.hasPrefix("/") ? path : "/" + path
        if !p.hasSuffix("/") { p += "/" }
        var comps = URLComponents(url: origin, resolvingAgainstBaseURL: false)!
        comps.path = basePath + p
        if !query.isEmpty { comps.queryItems = query }
        return comps.url!
    }

    static func clearCookies() {
        for c in HTTPCookieStorage.shared.cookies ?? [] where c.domain.contains("disify.dev") {
            HTTPCookieStorage.shared.deleteCookie(c)
        }
    }

    static var hasSession: Bool { !(HTTPCookieStorage.shared.cookies(for: origin.appendingPathComponent("povod/")) ?? []).isEmpty }

    @discardableResult
    static func send(_ method: String, _ path: String, json: [String: Any]? = nil, query: [URLQueryItem] = [], timeout: TimeInterval? = nil) async throws -> Data {
        var req = URLRequest(url: url(path, query: query))
        req.httpMethod = method
        if let timeout { req.timeoutInterval = timeout }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        // сервер отвечает по-русски (ошибки, ниши) — так и оставляем: тексты с сервера не переводим (I18N.md)
        req.setValue("ru", forHTTPHeaderField: "Accept-Language")
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        } else if method == "POST" {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = Data("{}".utf8)
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError(status: 0, message: String(localized: "нет ответа от сервера")) }
        if http.statusCode >= 400 { throw APIError(status: http.statusCode, message: errorText(data, status: http.statusCode)) }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], (obj["ok"] as? Bool) == false {
            throw APIError(status: http.statusCode, message: (obj["error"] as? String) ?? String(localized: "не получилось"))
        }
        return data
    }

    static func get<T: Decodable>(_ type: T.Type, _ path: String, query: [URLQueryItem] = []) async throws -> T {
        try decode(type, try await send("GET", path, query: query))
    }

    static func post<T: Decodable>(_ type: T.Type, _ path: String, json: [String: Any] = [:], timeout: TimeInterval? = nil) async throws -> T {
        try decode(type, try await send("POST", path, json: json, timeout: timeout))
    }

    static func getRaw(_ path: String) async throws -> [String: Any] {
        let d = try await send("GET", path)
        return (try? JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
    }

    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) } catch {
            throw APIError(status: 0, message: String(localized: "сервер ответил непонятно — обнови приложение"))
        }
    }

    static func errorText(_ data: Data, status: Int) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let e = obj["error"] as? String, !e.isEmpty { return e }
        switch status {
        case 401: return String(localized: "нужно войти заново")
        case 402: return String(localized: "нужен тариф — он оформляется на сайте Повода")
        case 403: return String(localized: "нет доступа")
        case 404: return String(localized: "не найдено")
        case 429: return String(localized: "слишком много попыток, подожди немного")
        default: return status >= 500 ? String(localized: "сервис недоступен, попробуй ещё раз") : String(localized: "ошибка \(status)")
        }
    }
}

struct APIError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

/// Запрос отменён (ушли с экрана, сменили вкладку, обновление перезапустилось) — это не ошибка сети, пользователю не показываем.
func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    let ns = error as NSError
    return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
}

func friendly(_ error: Error) -> String {
    if let e = error as? APIError { return e.message }
    if isCancellation(error) { return "" }
    let ns = error as NSError
    if ns.domain == NSURLErrorDomain {
        switch ns.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost: return String(localized: "нет интернета")
        case NSURLErrorTimedOut: return String(localized: "сервер долго не отвечает")
        default: return String(localized: "сеть недоступна")
        }
    }
    return error.localizedDescription
}
