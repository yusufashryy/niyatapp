import MessageUI
import SwiftUI
import UIKit

/// More › Send feedback: report a bug, suggest an idea, or flag something
/// inaccurate. Sends by email when `FEEDBACK_EMAIL` is set in
/// Config/Base.xcconfig and Mail is set up; otherwise opens a prefilled
/// GitHub issue.
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

            Section {
                Toggle("Include app details", isOn: $includeDetails)
            } footer: {
                Text("App version, iOS version, and your calculation method and Asr setting. Never your location.")
            }

            Section {
                Button {
                    send()
                } label: {
                    Label(sent ? "Thank you!" : "Send", systemImage: sent ? "checkmark.circle.fill" : "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    private var fullBody: String {
        var text = message
        if includeDetails {
            let info = Bundle.main.infoDictionary
            let version = info?["CFBundleShortVersionString"] as? String ?? "?"
            let build = info?["CFBundleVersion"] as? String ?? "?"
            text += """


            ---
            Niyat \(version) (\(build)) · iOS \(UIDevice.current.systemVersion) · \(UIDevice.current.model)
            Method: \(model.prayerSettings.method.title) · Asr: \(model.prayerSettings.madhab.title)
            """
        }
        return text
    }

    private func send() {
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
