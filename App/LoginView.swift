import SwiftUI

/// Вход: почта → код из письма (/api/auth/code, /api/auth/verify) или пароль (/api/auth/login).
struct LoginView: View {
    @Environment(Store.self) private var store
    @State private var email = UserDefaults.standard.string(forKey: "lastEmail") ?? ""
    @State private var password = ""
    @State private var code = ""
    @State private var step = 0
    @State private var passMode = false
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?
    enum Field { case email, pass, code }

    var body: some View {
        ZStack {
            MetalBackground(star: .big)
            VStack(alignment: .leading, spacing: 0) {
                StarLogo(size: 22).padding(.top, 24)
                Spacer(minLength: 120)
                if step == 0 { emailStep.transition(.move(edge: .leading).combined(with: .opacity)) } else { codeStep.transition(.move(edge: .trailing).combined(with: .opacity)) }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: step)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: passMode)
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("code") { email = "hi@disify.dev"; step = 1 }
            #endif
        }
    }

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("фирмы, которым есть повод написать")
                .font(Typo.display(30)).tracking(-1).lineSpacing(2).foregroundStyle(Pal.ink)
            Text("Вход в кабинет: компании, подборки и сбор базы.")
                .font(Typo.body(16)).foregroundStyle(Pal.fg2).padding(.top, 10).padding(.bottom, 18)
            VStack(spacing: 12) {
                field(String(localized: "почта"), text: $email, secure: false)
                    .focused($focus, equals: .email)
                    .textContentType(.username).keyboardType(.emailAddress)
                    .submitLabel(passMode ? .next : .go)
                    .onSubmit { if passMode { focus = .pass } else { submit() } }
                if passMode {
                    field(String(localized: "пароль"), text: $password, secure: true)
                        .focused($focus, equals: .pass)
                        .textContentType(.password).submitLabel(.go).onSubmit(submit)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let error {
                    Text(error).font(Typo.body(14)).foregroundStyle(Pal.danger).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                }
                Button(action: submit) {
                    ZStack { if busy { ProgressView().tint(.white) } else { Text(passMode ? "войти" : "получить код").font(Typo.body(17, .semibold)) } }
                        .frame(maxWidth: .infinity).frame(minHeight: 54).primaryFill()
                }
                .buttonStyle(PressStyle()).disabled(busy)
                Button { passMode.toggle(); error = nil; haptic() } label: {
                    Text(passMode ? "войти по коду из письма" : "войти по паролю").font(Typo.body(15, .medium)).foregroundStyle(Pal.ink).frame(minHeight: 40)
                }
            }
            .padding(16)
            .glassRect(30, .light)
            Text("Аккаунт создаётся на сайте Повода.\nВход — той же почтой, что на disify.dev/povod.")
                .font(Typo.body(13)).foregroundStyle(Pal.fg2).multilineTextAlignment(.center).lineSpacing(3)
                .frame(maxWidth: .infinity).padding(.top, 14)
        }
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("код из письма").font(Typo.display(30)).tracking(-1).foregroundStyle(Pal.ink)
            Text("Отправили 6 цифр на \(email). Письмо может идти до минуты.")
                .font(Typo.body(16)).foregroundStyle(Pal.fg2).lineSpacing(3).padding(.top, 10).padding(.bottom, 18)
            VStack(spacing: 12) {
                ZStack {
                    HStack(spacing: 0) {
                        ForEach(0..<6, id: \.self) { i in
                            let chars = Array(code)
                            Text(i < chars.count ? String(chars[i]) : "")
                                .font(Typo.mono(24)).foregroundStyle(Pal.ink)
                                .frame(width: 48, height: 58)
                                .glass(.light, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Pal.ink.opacity(i == min(code.count, 5) && focus == .code ? 0.55 : 0), lineWidth: 2))
                                .scaleEffect(i < chars.count ? 1 : 0.97)
                                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: chars.count)
                            if i < 5 { Spacer(minLength: 4) }
                        }
                    }
                    TextField("", text: $code)
                        .keyboardType(.numberPad).textContentType(.oneTimeCode)
                        .focused($focus, equals: .code)
                        .foregroundStyle(.clear).tint(.clear).opacity(0.02)
                        .onChange(of: code) { _, v in
                            let digits = String(v.filter(\.isNumber).prefix(6))
                            if digits != v { code = digits }
                            if digits.count == 6 { verify() }
                        }
                }
                .frame(minHeight: 58)
                .contentShape(Rectangle())
                .onTapGesture { focus = .code }
                if let error { Text(error).font(Typo.body(14)).foregroundStyle(Pal.danger) }
                Button {
                    if let s = UIPasteboard.general.string { code = String(s.filter(\.isNumber).prefix(6)) }
                } label: {
                    ZStack { if busy { ProgressView().tint(Pal.ink) } else { Text("вставить код из письма").font(Typo.body(16, .semibold)) } }
                        .foregroundStyle(Pal.ink).frame(maxWidth: .infinity).frame(minHeight: 54).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .glass(.light, in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
                HStack {
                    Button { step = 0; code = ""; error = nil } label: { Text("другая почта").font(Typo.body(15, .medium)).foregroundStyle(Pal.ink).frame(minHeight: 40) }
                    Spacer()
                    Button { requestCode(resend: true) } label: { Text("прислать ещё раз").font(Typo.body(15, .medium)).foregroundStyle(Pal.fg2).frame(minHeight: 40) }
                }
                .padding(.horizontal, 6)
            }
            .padding(16)
            .glassRect(30, .light)
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focus = .code } }
    }

    @ViewBuilder
    private func field(_ placeholder: String, text: Binding<String>, secure: Bool) -> some View {
        Group {
            if secure {
                SecureField("", text: text, prompt: Text(placeholder).foregroundColor(Pal.fg3))
            } else {
                TextField("", text: text, prompt: Text(placeholder).foregroundColor(Pal.fg3))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
        }
        .font(Typo.body(17)).foregroundStyle(Pal.ink)
        .padding(.horizontal, 16).frame(minHeight: 54)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Pal.surface.opacity(0.78)))
    }

    private var cleanEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    private func submit() {
        guard !busy else { return }
        guard cleanEmail.contains("@"), cleanEmail.contains(".") else { withAnimation { error = String(localized: "впиши почту") }; return }
        UserDefaults.standard.set(cleanEmail, forKey: "lastEmail")
        if passMode {
            guard !password.isEmpty else { withAnimation { error = String(localized: "впиши пароль") }; return }
            busy = true; error = nil
            Task {
                defer { busy = false }
                do {
                    try await API.send("POST", "/api/auth/login/", json: ["email": cleanEmail, "password": password])
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    await store.didLogin()
                } catch {
                    withAnimation { self.error = friendly(error) }
                }
            }
        } else {
            requestCode(resend: false)
        }
    }

    private func requestCode(resend: Bool) {
        guard !busy else { return }
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                try await API.send("POST", "/api/auth/code/", json: ["email": cleanEmail, "mode": "login"])
                if resend { store.show(String(localized: "новый код отправлен")) }
                withAnimation { step = 1 }
            } catch {
                withAnimation { self.error = friendly(error) }
            }
        }
    }

    private func verify() {
        guard !busy, code.count == 6 else { return }
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                try await API.send("POST", "/api/auth/verify/", json: ["email": cleanEmail, "code": code, "mode": "login"])
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                focus = nil
                await store.didLogin()
            } catch {
                withAnimation { self.error = friendly(error) }
                code = ""
            }
        }
    }
}
