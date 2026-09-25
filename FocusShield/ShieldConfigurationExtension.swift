import ManagedSettings
import ManagedSettingsUI
import UIKit

/// The screen shown when you open a locked app during prayer time.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }

    private func makeConfiguration() -> ShieldConfiguration {
        let title: String
        if let prayer = FocusStore.activePrayer {
            title = "It's time for \(prayer.displayName(on: .now))"
        } else {
            title = "Time to focus"
        }

        var subtitle = "“The prayer is obligatory for believers at specific times.” (Quran 4:103)"
        if let until = FocusStore.lockedUntil {
            subtitle += "\n\nUnlocks at \(until.shortTime). Prayed already? Open Salah and tap “I've prayed”."
        }

        let green = UIColor(red: 0.047, green: 0.353, blue: 0.294, alpha: 1)
        let gold = UIColor(red: 0.851, green: 0.690, blue: 0.345, alpha: 1)

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: green,
            icon: UIImage(systemName: "moon.stars.fill")?.withTintColor(gold, renderingMode: .alwaysOriginal),
            title: ShieldConfiguration.Label(text: title, color: .white),
            subtitle: ShieldConfiguration.Label(text: subtitle, color: UIColor.white.withAlphaComponent(0.85)),
            primaryButtonLabel: ShieldConfiguration.Label(text: "OK", color: green),
            primaryButtonBackgroundColor: gold,
            secondaryButtonLabel: nil
        )
    }
}
