import MessageUI
import SwiftUI
import UIKit

/// More › Send feedback: report a bug, suggest an idea, or flag something
/// inaccurate. Where it goes, in order:
/// 1. A Discord channel, if `DISCORD_WEBHOOK` is set (in Config/Local.xcconfig);
/// 2. email, if `FEEDBACK_EMAIL` is set and Mail is set up;
/// 3. otherwise a prefilled GitHub issue.
struct FeedbackView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case idea = "Idea or request"
        case bug = "Something isn't working"
        case accuracy = "Prayer time, Qibla or Qur'an accuracy"
        case other = "Something else"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .idea: "lightbulb.fill"
            case .bug: "ladybug.fill"
            case .accuracy: "checkmark.seal.fill"
            case .other: "ellipsis.bubble.fill"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppModel.self) private var model
    @State private var kind = Kind.idea
    @State private var message = ""
    @State private var includeDetails = true
    @State private var showMail = false
    @State private var sent = false
    @State private var replyEmail = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $kind) {
                    ForEach(Kind.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("What's it about?")
            }

            Section {
                TextField(placeholder, text: $message, axis: .vertical)
                    .lineLimit(5...12)
            } header: {
                Text("Your message")
            } footer: {
                if kind == .accuracy {
                    Text("Accuracy matters most to us. For prayer times, say what your local mosque shows. For the Qur'an, give the surah and verse.")
                }
            }

            if FeedbackSender.discordWebhook != nil {
                Section {
                    TextField("Email (optional)", text: $replyEmail)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Want a reply?")
                } footer: {
                    Text("Only if you'd like an answer. It's used to reply to this message and nothing else.")
                }
            }

            Section {
                Toggle("Include app details", isOn: $includeDetails)
            } footer: {
                Text("App version, iOS version, and your calculation method and Asr setting. Never your location.")
            }

            Section {
                Button {
                    send()
                } label: {
                    Group {
                        if isSending {
                            ProgressView()
                        } else {
                            Label(sent ? "Sent. Thank you!" : "Send", systemImage: sent ? "checkmark.circle.fill" : "paperplane.fill")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending || sent)
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.orange)
                }
                .haptic(.success, trigger: sent)
            }
        }
        .scrollContentBackground(.hidden)
        .niyatBackground()
        .navigationTitle("Send feedback")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showMail) {
            MailComposer(recipient: Self.email ?? "", subject: subject, body: fullBody) { didSend in
                if didSend { sent = true }
            }
            .ignoresSafeArea()
        }
    }

    private var placeholder: String {
        switch kind {
        case .idea: "What would make Niyat better for you?"
        case .bug: "What happened, and what did you expect?"
        case .accuracy: "What looks wrong, and where are you?"
        case .other: "Tell us anything"
        }
    }

    private static var email: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "NiyatFeedbackEmail") as? String
        return value?.contains("@") == true ? value : nil
    }

    private var subject: String { "Niyat feedback: \(kind.rawValue)" }

    private var details: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return """
        Niyat \(version) (\(build)) · iOS \(UIDevice.current.systemVersion) · \(UIDevice.current.model)
        Method: \(model.prayerSettings.method.title) · Asr: \(model.prayerSettings.madhab.title)
        """
    }

    private var fullBody: String {
        includeDetails ? message + "\n\n---\n" + details : message
    }

    private func send() {
        if FeedbackSender.discordWebhook != nil {
            isSending = true
            errorMessage = nil
            Task {
                let result = await FeedbackSender.sendToDiscord(kind: kind.rawValue, message: message,
                                                               replyTo: replyEmail, details: includeDetails ? details : nil)
                isSending = false
                switch result {
                case .success: sent = true
                case .failure(let error): errorMessage = error.message
                }
            }
            return
        }
        if Self.email != nil, MFMailComposeViewController.canSendMail() {
            showMail = true
            return
        }
        var components = URLComponents(string: "https://github.com/yusufashryy/niyatapp/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "title", value: subject),
            URLQueryItem(name: "body", value: fullBody),
        ]
        if let url = components?.url {
            openURL(url)
            sent = true
        }
    }
}

/// Posts feedback to a Discord channel through a webhook.
///
/// A webhook URL inside an app can be extracted by a determined person, so:
/// keep it out of the public repo (Config/Local.xcconfig, which is
/// git-ignored), use a channel only for feedback, and if it's ever abused,
/// delete the webhook in Discord and make a new one. Mentions are disabled
/// so nobody can ping @everyone through it, and the app limits how often it
/// can be used.
enum FeedbackSender {
    struct Failure: Error { let message: String }

    static var discordWebhook: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "NiyatDiscordWebhook") as? String,
              value.contains("discord.com/api/webhooks/") else { return nil }
        // Stored without "https://" because "//" starts a comment in .xcconfig files.
        return URL(string: value.hasPrefix("https://") ? value : "https://" + value)
    }

    private static let recentKey = "feedback.recentSends"

    static func sendToDiscord(kind: String, message: String, replyTo: String, details: String?) async -> Result<Void, Failure> {
        guard let url = discordWebhook else { return .failure(Failure(message: "Feedback isn't set up.")) }

        // At most one message a minute and ten a day from this phone.
        let now = Date.now
        var recent = (UserDefaults.standard.array(forKey: recentKey) as? [Date] ?? []).filter { now.timeIntervalSince($0) < 86_400 }
        if let last = recent.max(), now.timeIntervalSince(last) < 60 {
            return .failure(Failure(message: "Please wait a minute before sending another message."))
        }
        if recent.count >= 10 {
            return .failure(Failure(message: "You've sent a lot of feedback today. Thank you! Please try again tomorrow."))
        }

        var fields: [[String: Any]] = [["name": "Type", "value": kind, "inline": true]]
        let reply = replyTo.trimmingCharacters(in: .whitespaces)
        if !reply.isEmpty { fields.append(["name": "Reply to", "value": String(reply.prefix(200)), "inline": true]) }
        if let details { fields.append(["name": "Details", "value": String(details.prefix(1000))]) }
        let payload: [String: Any] = [
            "username": "Niyat Feedback",
            "allowed_mentions": ["parse": [String]()],
            "embeds": [[
                "title": kind,
                "description": String(message.prefix(3900)),
                "color": 0xD4AF37,
                "fields": fields,
                "timestamp": ISO8601DateFormatter().string(from: now),
            ]],
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .failure(Failure(message: "Couldn't send right now. Please try again later."))
            }
            recent.append(now)
            UserDefaults.standard.set(recent, forKey: recentKey)
            return .success(())
        } catch {
            return .failure(Failure(message: "Couldn't send. Check your internet connection and try again."))
        }
    }
}

/// Apple's Mail compose screen.
private struct MailComposer: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    let onFinish: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([recipient])
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            onFinish(result == .sent)
            controller.dismiss(animated: true)
        }
    }
}
