import Foundation
import CryptoKit
import SwiftUI

/// Сколько секунд данные считаются свежими: при открытии экрана / переключении вкладок не перезапрашиваем.
/// «Потянуть вниз» грузит всегда.
enum CachePolicy {
    static let freshFor: TimeInterval = 60
}

/// Последние ответы сервера на телефоне (stale-while-revalidate): при запуске и открытии экрана сразу показываем
/// сохранённую копию, свежие данные приходят в фоне. Файлы: Caches/povod-cache/<sha256 почты>/<ключ>.json.
/// Хранится сам JSON ответа сервера — декодируется теми же моделями, что и живой ответ.
/// Выключен, пока `account == nil`: до входа и в режиме снимков CI (-fixture). Стирается при выходе и удалении аккаунта.
enum DiskCache {
    /// чей кэш сейчас читаем и пишем (почта в нижнем регистре); nil — кэш выключен
    static var account: String?

    private static let lastAccountKey = "povod.cache.account"
    private static let queue = DispatchQueue(label: "povod.disk-cache", qos: .utility)

    /// аккаунт прошлого запуска — чтобы показать его копию до ответа /auth/me
    static var lastAccount: String? {
        get { UserDefaults.standard.string(forKey: lastAccountKey) }
        set {
            if let v = newValue { UserDefaults.standard.set(v, forKey: lastAccountKey) } else { UserDefaults.standard.removeObject(forKey: lastAccountKey) }
        }
    }

    private static var root: URL? {
        guard let base: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("povod-cache", isDirectory: true)
    }

    private static func folder(_ who: String) -> URL? {
        let digest = SHA256.hash(data: Data(who.lowercased().utf8))
        let name: String = digest.map { (b: UInt8) -> String in String(format: "%02x", b) }.joined()
        return root?.appendingPathComponent(name, isDirectory: true)
    }

    private static func file(_ key: String, who: String) -> URL? {
        let safe: String = String(key.map { (c: Character) -> Character in
            (c.isASCII && (c.isLetter || c.isNumber)) || c == "." || c == "-" ? c : "_"
        })
        return folder(who)?.appendingPathComponent(safe + ".json")
    }

    /// прочитать копию (для `who` или текущего аккаунта)
    static func read(_ key: String, who: String? = nil) -> Data? {
        guard let acc: String = who ?? account, let u: URL = file(key, who: acc) else { return nil }
        return try? Data(contentsOf: u)
    }

    /// сохранить ответ сервера (в фоне, атомарно)
    static func write(_ data: Data, _ key: String) {
        guard let acc: String = account, let u: URL = file(key, who: acc) else { return }
        let dir: URL = u.deletingLastPathComponent()
        queue.async {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: u, options: [.atomic])
        }
    }

    static func remove(_ key: String) {
        guard let acc: String = account, let u: URL = file(key, who: acc) else { return }
        queue.async { try? FileManager.default.removeItem(at: u) }
    }

    /// стереть всё (выход, удаление аккаунта, смена аккаунта): следующий человек на телефоне ничего не увидит
    static func clearAll() {
        account = nil
        lastAccount = nil
        guard let r: URL = root else { return }
        queue.async { try? FileManager.default.removeItem(at: r) }
    }
}

/// Одна загрузка за раз по ключу + «свежесть»: второй одновременный вызов ждёт первый, а не шлёт запрос ещё раз;
/// данные моложе `CachePolicy.freshFor` без `force` не перезапрашиваем.
@MainActor
final class LoadGate {
    private var at: [String: Date] = [:]
    private var running: [String: Task<Bool, Never>] = [:]
    /// растёт при сбросе (выход): ответ запроса, начатого до сброса, не отмечается свежим
    private var gen = 0

    func isFresh(_ key: String) -> Bool {
        guard let t: Date = at[key] else { return false }
        return Date().timeIntervalSince(t) < CachePolicy.freshFor
    }

    /// `work` возвращает true, если сервер ответил (тогда ключ считается свежим).
    /// Без force — хватает уже идущего запроса. С force (после действия, «потянуть вниз») нужен ответ, начатый после вызова:
    /// дожидаемся идущего и шлём свой (если за это время не начал кто-то другой — тогда ждём его).
    func run(_ key: String, force: Bool, _ work: @escaping @MainActor () async -> Bool) async {
        if let t: Task<Bool, Never> = running[key] {
            _ = await t.value
            if !force { return }
            if let other: Task<Bool, Never> = running[key], other != t {
                _ = await other.value
                return
            }
        } else if !force && isFresh(key) {
            return
        }
        let myGen: Int = gen
        let task: Task<Bool, Never> = Task { @MainActor in await work() }
        running[key] = task
        let ok: Bool = await task.value
        guard myGen == gen else { return }
        if running[key] == task { running[key] = nil }
        if ok { at[key] = Date() }
    }

    func reset() {
        gen += 1
        for t in running.values { t.cancel() }
        running = [:]
        at = [:]
    }
}

// MARK: - скелетоны (первый вход без копии на телефоне)

/// Мягкий перелив по заглушкам; при «уменьшить движение» — без анимации.
struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { (geo: GeometryProxy) in
                        shine(width: geo.size.width)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }

    private func shine(width: CGFloat) -> some View {
        let colors: [Color] = [Color.white.opacity(0), Color.white.opacity(0.35), Color.white.opacity(0)]
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
            .frame(width: width * 0.6)
            .offset(x: phase * width * 1.3)
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}

/// Серая полоска-заглушка вместо текста.
struct SkeletonBar: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12
    var body: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Pal.ink.opacity(0.09))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

/// Строки-заглушки списка (компании, письма, подборки, сигналы) — пока нет ни копии, ни ответа сервера.
struct SkeletonRows: View {
    var count: Int = 5
    /// карточки по отдельности (компании, сигналы) или строки в одной группе (письма, подборки)
    var cards: Bool = false

    var body: some View {
        VStack(spacing: cards ? 8 : 0) {
            ForEach(0..<count, id: \.self) { (i: Int) in
                row(i)
            }
        }
        .shimmer()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("загружаем…"))
    }

    private func row(_ i: Int) -> some View {
        let w1: CGFloat = [170, 130, 200, 150, 120, 180][i % 6]
        let w2: CGFloat = [230, 190, 250, 210, 170, 240][i % 6]
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SkeletonBar(width: w1, height: 14)
                Spacer(minLength: 0)
                SkeletonBar(width: 40, height: 10)
            }
            SkeletonBar(width: w2, height: 10)
            SkeletonBar(width: w2 * 0.6, height: 10)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if cards { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Pal.surface.opacity(0.45)) }
        }
        .overlay(alignment: .top) {
            if !cards && i > 0 { Rectangle().fill(Pal.line).frame(height: 0.5).padding(.leading, 16) }
        }
    }
}

/// Тихая строка «не обновилось — показана сохранённая копия» (ошибка фоновой загрузки при данных на экране).
struct StaleNote: View {
    let why: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.clockwise.icloud").font(.system(size: 12, weight: .semibold)).accessibilityHidden(true)
            Text("не обновилось: \(why) — потяните вниз, чтобы повторить").lineLimit(2)
        }
        .font(Typo.body(13))
        .foregroundStyle(Pal.fg3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
