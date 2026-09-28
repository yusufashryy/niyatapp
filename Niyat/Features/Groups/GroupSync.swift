import Foundation
import Observation

#if GROUPS
import CloudKit
#endif

/// What a member shares with their groups: summary counts only, never reasons,
/// notes or which specific prayers.
struct MemberSnapshot: Equatable {
    var displayName: String
    var dayKey: String
    /// -1 means the member chose not to share this.
    var prayersToday: Int
    var prayerStreak: Int
    var quranToday: Int
    var quranGoal: Int
    var quranGoalComplete: Bool
    var quranStreak: Int
    var quranWeek: Int
    var updatedAt: Date
}

/// A group and its members, as shown in the Groups screen.
struct AccountabilityGroup: Identifiable, Equatable {
    let id: String
    var name: String
    var isOwner: Bool
    var members: [Member]

    struct Member: Identifiable, Equatable {
        let id: String
        var snapshot: MemberSnapshot
        var isMe: Bool
    }
}

/// Keeps your summary up to date in every group you're in.
/// Groups use CloudKit sharing, which needs the paid build (`make full`); in the
/// free build this is a harmless no-op.
@MainActor
@Observable
final class GroupSync {
    static let shared = GroupSync()

    private(set) var groups: [AccountabilityGroup] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// What you choose to share.
    var sharePrayers: Bool {
        get { sharePrayersValue }
        set { sharePrayersValue = newValue; UserDefaults.standard.set(newValue, forKey: "groups.sharePrayers"); publishSoon() }
    }
    var shareQuran: Bool {
        get { shareQuranValue }
        set { shareQuranValue = newValue; UserDefaults.standard.set(newValue, forKey: "groups.shareQuran"); publishSoon() }
    }
    var displayName: String {
        get { displayNameValue }
        set { displayNameValue = newValue; UserDefaults.standard.set(newValue, forKey: "groups.displayName") }
    }

    private var sharePrayersValue = UserDefaults.standard.object(forKey: "groups.sharePrayers") as? Bool ?? true
    private var shareQuranValue = UserDefaults.standard.object(forKey: "groups.shareQuran") as? Bool ?? true
    private var displayNameValue = UserDefaults.standard.string(forKey: "groups.displayName") ?? ""

    @ObservationIgnored private var publishTask: Task<Void, Never>?

    static var isAvailable: Bool {
        #if GROUPS
        // The automated UI tour runs an unsigned build with no iCloud
        // entitlement, where touching CloudKit crashes the app.
        !ProcessInfo.processInfo.arguments.contains("-demo")
        #else
        false
        #endif
    }

    private init() {}

    /// Your current summary, built from the prayer journal and Qur'an progress.
    func mySnapshot(now: Date = .now) -> MemberSnapshot {
        let records = PrayerLog.load()
        let today = Calendar.current.startOfDay(for: now)
        let prayed = PrayerName.obligatory.filter { records[PrayerLog.key($0, on: today)]?.status.countsAsPrayed ?? false }.count
        let quran = QuranProgress.day(now)
        return MemberSnapshot(
            displayName: displayName.isEmpty ? "Me" : displayName,
            dayKey: QuranProgress.dayKey(for: now),
            prayersToday: sharePrayers ? prayed : -1,
            prayerStreak: sharePrayers ? prayerStreak(records: records, asOf: today) : -1,
            quranToday: shareQuran ? quran.count : -1,
            quranGoal: shareQuran ? (QuranProgress.dailyGoal ?? 0) : -1,
            quranGoalComplete: shareQuran && quran.isComplete,
            quranStreak: shareQuran ? QuranProgress.currentStreak(asOf: now) : -1,
            quranWeek: shareQuran ? QuranProgress.totals(lastDays: 7, asOf: now).ayat : -1,
            updatedAt: now
        )
    }

    private func prayerStreak(records: [String: PrayerRecord], asOf today: Date) -> Int {
        let calendar = Calendar.current
        func complete(_ day: Date) -> Bool {
            PrayerName.obligatory.allSatisfy { records[PrayerLog.key($0, on: day)]?.status.keepsStreak ?? false }
        }
        var day = today
        if !complete(day) { day = calendar.date(byAdding: .day, value: -1, to: day) ?? day }
        var count = 0
        while complete(day), count < 10_000 {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return count
    }

    /// Publishes your summary a few seconds after the last change (so reading
    /// ten verses sends one update, not ten).
    func publishSoon() {
        guard Self.isAvailable else { return }
        publishTask?.cancel()
        publishTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await publishNow()
        }
    }

    #if GROUPS
    // MARK: - CloudKit

    /// The container named in the entitlements (Config/full-features.yml).
    /// Not `CKContainer.default()`: that one is "iCloud.<bundle ID>", which the
    /// app isn't allowed to use, so iCloud refuses with "Couldn't get container
    /// configuration".
    @ObservationIgnored private lazy var container: CKContainer = {
        if let id = Bundle.main.object(forInfoDictionaryKey: "NiyatCloudContainer") as? String,
           id.hasPrefix("iCloud."), !id.contains("$(") {
            return CKContainer(identifier: id)
        }
        return CKContainer.default()
    }()
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }
    private static let zonePrefix = "Group-"

    private func myUserID() async throws -> String {
        try await container.userRecordID().recordName
    }

    private func checkAccount() async -> Bool {
        guard Self.isAvailable else { return false }
        let status = try? await container.accountStatus()
        guard status == .available else {
            errorMessage = "Sign in to iCloud in the iPhone Settings app to use Groups."
            return false
        }
        return true
    }

    func refresh() async {
        guard await checkAccount() else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let me = try await myUserID()
            var result: [AccountabilityGroup] = []
            let owned = try await privateDB.allRecordZones().filter { $0.zoneID.zoneName.hasPrefix(Self.zonePrefix) }
            for zone in owned {
                if let group = try await loadGroup(zoneID: zone.zoneID, database: privateDB, me: me, isOwner: true) {
                    result.append(group)
                }
            }
            for zone in try await sharedDB.allRecordZones() where zone.zoneID.zoneName.hasPrefix(Self.zonePrefix) {
                if let group = try await loadGroup(zoneID: zone.zoneID, database: sharedDB, me: me, isOwner: false) {
                    result.append(group)
                }
            }
            groups = result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load your groups: \(error.localizedDescription)"
        }
    }

    private func loadGroup(zoneID: CKRecordZone.ID, database: CKDatabase, me: String, isOwner: Bool) async throws -> AccountabilityGroup? {
        let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: nil)
        var name = "Group"
        var members: [AccountabilityGroup.Member] = []
        for (_, result) in changes.modificationResultsByID {
            guard case .success(let modification) = result else { continue }
            let record = modification.record
            switch record.recordType {
            case "Group":
                name = record["name"] as? String ?? name
            case CKRecord.SystemType.share:
                // The invite carries the name too.
                if name == "Group", let title = record[CKShare.SystemFieldKey.title] as? String, !title.isEmpty { name = title }
            case "Member":
                // Only trust a member record written by the person it belongs to.
                let ownerID = String(record.recordID.recordName.dropFirst("member-".count))
                let creator = record.creatorUserRecordID?.recordName
                let lastEditor = record.lastModifiedUserRecordID?.recordName
                let resolvedOwner = ownerID == me ? CKCurrentUserDefaultName : ownerID
                guard creator == resolvedOwner || creator == ownerID,
                      lastEditor == nil || lastEditor == creator else { continue }
                members.append(AccountabilityGroup.Member(id: ownerID, snapshot: Self.snapshot(from: record), isMe: ownerID == me))
            default:
                continue
            }
        }
        members.sort { $0.isMe != $1.isMe ? $0.isMe : $0.snapshot.displayName < $1.snapshot.displayName }
        return AccountabilityGroup(id: zoneID.zoneName, name: name, isOwner: isOwner, members: members)
    }

    func createGroup(named name: String) async -> CKShare? {
        guard await checkAccount() else { return nil }
        do {
            let me = try await myUserID()
            let zone = CKRecordZone(zoneName: Self.zonePrefix + UUID().uuidString)
            _ = try await privateDB.save(zone)
            let group = CKRecord(recordType: "Group", recordID: CKRecord.ID(recordName: "group", zoneID: zone.zoneID))
            group["name"] = name
            let member = memberRecord(me: me, zoneID: zone.zoneID)
            let share = CKShare(recordZoneID: zone.zoneID)
            share[CKShare.SystemFieldKey.title] = name
            share.publicPermission = .none
            do {
                // Each record can fail on its own without the call throwing:
                // check them, and hand back the share iCloud actually saved.
                let (saved, _) = try await privateDB.modifyRecords(saving: [share, group, member], deleting: [])
                var savedShare: CKShare?
                for (_, result) in saved {
                    switch result {
                    case .success(let record): if let record = record as? CKShare { savedShare = record }
                    case .failure(let error): throw error
                    }
                }
                guard let savedShare else { throw CKError(.internalError) }
                await refresh()
                return savedShare
            } catch {
                // Don't leave an empty group behind.
                _ = try? await privateDB.deleteRecordZone(withID: zone.zoneID)
                throw error
            }
        } catch {
            await refresh()
            errorMessage = "Couldn't create the group: \(Self.explain(error))"
            return nil
        }
    }

    /// A readable reason, including the one a developer can fix: the Groups
    /// record types not yet deployed to iCloud's production environment.
    private static func explain(_ error: Error) -> String {
        let text = error.localizedDescription
        if text.localizedCaseInsensitiveContains("production schema") || text.localizedCaseInsensitiveContains("record type") {
            return "Groups isn't set up on iCloud yet. Please try again later. (\(text))"
        }
        return text
    }

    /// The share for a group you own, for inviting people.
    func share(for group: AccountabilityGroup) async -> CKShare? {
        let zoneID = CKRecordZone.ID(zoneName: group.id, ownerName: CKCurrentUserDefaultName)
        do {
            return try await privateDB.record(for: CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)) as? CKShare
        } catch {
            errorMessage = "Couldn't open this group's invite: \(Self.explain(error)). Try deleting the group and creating it again."
            return nil
        }
    }

    var cloudContainer: CKContainer { container }

    /// Owners delete the group for everyone; members just leave.
    func leave(_ group: AccountabilityGroup) async {
        do {
            if group.isOwner {
                let zoneID = CKRecordZone.ID(zoneName: group.id, ownerName: CKCurrentUserDefaultName)
                try await privateDB.deleteRecordZone(withID: zoneID)
            } else if let zone = try await sharedDB.allRecordZones().first(where: { $0.zoneID.zoneName == group.id }) {
                try await sharedDB.deleteRecordZone(withID: zone.zoneID)
            }
            await refresh()
        } catch {
            errorMessage = "Couldn't leave the group: \(error.localizedDescription)"
        }
    }

    /// Accepts an invitation opened from Messages/Mail.
    func accept(_ metadata: CKShare.Metadata) async {
        do {
            _ = try await CKContainer(identifier: metadata.containerIdentifier).accept(metadata)
            await publishNow()
            await refresh()
        } catch {
            errorMessage = "Couldn't join the group: \(error.localizedDescription)"
        }
    }

    func publishNow() async {
        guard Self.isAvailable, (try? await container.accountStatus()) == .available, let me = try? await myUserID() else { return }
        let owned = (try? await privateDB.allRecordZones()) ?? []
        for zone in owned where zone.zoneID.zoneName.hasPrefix(Self.zonePrefix) {
            _ = try? await privateDB.modifyRecords(saving: [memberRecord(me: me, zoneID: zone.zoneID)], deleting: [],
                                                    savePolicy: .allKeys)
        }
        let joined = (try? await sharedDB.allRecordZones()) ?? []
        for zone in joined where zone.zoneID.zoneName.hasPrefix(Self.zonePrefix) {
            _ = try? await sharedDB.modifyRecords(saving: [memberRecord(me: me, zoneID: zone.zoneID)], deleting: [],
                                                   savePolicy: .allKeys)
        }
    }

    private func memberRecord(me: String, zoneID: CKRecordZone.ID) -> CKRecord {
        let snapshot = mySnapshot()
        let record = CKRecord(recordType: "Member", recordID: CKRecord.ID(recordName: "member-\(me)", zoneID: zoneID))
        record["displayName"] = snapshot.displayName
        record["dayKey"] = snapshot.dayKey
        record["prayersToday"] = snapshot.prayersToday
        record["prayerStreak"] = snapshot.prayerStreak
        record["quranToday"] = snapshot.quranToday
        record["quranGoal"] = snapshot.quranGoal
        record["quranGoalComplete"] = snapshot.quranGoalComplete ? 1 : 0
        record["quranStreak"] = snapshot.quranStreak
        record["quranWeek"] = snapshot.quranWeek
        record["updatedAt"] = snapshot.updatedAt
        return record
    }

    private static func snapshot(from record: CKRecord) -> MemberSnapshot {
        let today = QuranProgress.dayKey(for: .now)
        let dayKey = record["dayKey"] as? String ?? ""
        // Daily numbers from a previous day mean "nothing yet today".
        let isToday = dayKey == today
        return MemberSnapshot(
            displayName: record["displayName"] as? String ?? "Member",
            dayKey: dayKey,
            prayersToday: isToday ? (record["prayersToday"] as? Int ?? -1) : min(record["prayersToday"] as? Int ?? -1, 0),
            prayerStreak: record["prayerStreak"] as? Int ?? -1,
            quranToday: isToday ? (record["quranToday"] as? Int ?? -1) : min(record["quranToday"] as? Int ?? -1, 0),
            quranGoal: record["quranGoal"] as? Int ?? -1,
            quranGoalComplete: isToday && (record["quranGoalComplete"] as? Int ?? 0) == 1,
            quranStreak: record["quranStreak"] as? Int ?? -1,
            quranWeek: record["quranWeek"] as? Int ?? -1,
            updatedAt: record["updatedAt"] as? Date ?? .distantPast
        )
    }
    #else
    func refresh() async {}
    func publishNow() async {}
    #endif
}
