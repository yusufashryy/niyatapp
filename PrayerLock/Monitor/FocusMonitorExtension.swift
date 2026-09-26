import DeviceActivity
import Foundation

/// iOS runs this in the background at the start and end of each prayer window.
final class FocusMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        FocusScheduler.handleIntervalStart(activity)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        FocusScheduler.handleIntervalEnd(activity)
    }
}
