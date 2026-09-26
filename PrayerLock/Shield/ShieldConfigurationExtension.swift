import ManagedSettings
import ManagedSettingsUI
import SwiftUI
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
            subtitle += "\n\nUnlocks at \(until.shortTime). Prayed already? Open Niyat and tap “I've prayed”."
        }

        let background = UIColor(Palette.glow)
        let gold = UIColor(Palette.highlight)

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: background,
            icon: UIImage(systemName: "moon.stars.fill")?.withTintColor(gold, renderingMode: .alwaysOriginal),
            title: ShieldConfiguration.Label(text: title, color: .white),
            subtitle: ShieldConfiguration.Label(text: subtitle, color: UIColor.white.withAlphaComponent(0.85)),
            primaryButtonLabel: ShieldConfiguration.Label(text: "OK", color: .black),
            primaryButtonBackgroundColor: gold,
            secondaryButtonLabel: nil
        )
    }
}
