import SwiftUI

#if GROUPS
import CloudKit
import UIKit

/// Groups: private accountability circles with family and friends.
struct GroupsView: View {
    @State private var sync = GroupSync.shared
    @State private var newGroupName = ""
    @State private var showCreate = false
    @State private var sharing: ShareItem?
    @State private var leaving: AccountabilityGroup?

    struct ShareItem: Identifiable {
        let id = UUID()
        let share: CKShare
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                intro
                    .appearAnimation(0)

                if let error = sync.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(14)
                        .surface(cornerRadius: 18)
                }

                ForEach(Array(sync.groups.enumerated()), id: \.element.id) { index, group in
                    GroupCard(group: group) {
                        Task {
                            if let share = await sync.share(for: group) { sharing = ShareItem(share: share) }
                        }
                    } onLeave: {
                        leaving = group
                    }
                    .appearAnimation(1 + index)
                }

                if sync.groups.isEmpty, !sync.isLoading {
                    VStack(spacing: 10) {
                        Rosette(color: Palette.highlight.opacity(0.4)).frame(width: 70, height: 70)
                        Text("No groups yet").font(.headline)
                        Text("Create one and invite family or friends to encourage each other.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .surface(cornerRadius: 26)
                }

                privacySection
            }
            .padding(16)
        }
        .refreshable { await sync.refresh() }
        .niyatBackground()
        .navigationTitle("Groups")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Create a group")
            }
        }
        .alert("New group", isPresented: $showCreate) {
            TextField("Name, e.g. Family", text: $newGroupName)
            Button("Create") {
                let name = newGroupName.trimmingCharacters(in: .whitespaces)
                newGroupName = ""
                Task {
                    if let share = await sync.createGroup(named: name.isEmpty ? "My group" : name) {
                        sharing = ShareItem(share: share)
                    }
                }
            }
            Button("Cancel", role: .cancel) { newGroupName = "" }
        } message: {
            Text("You can invite people right after.")
        }
        .confirmationDialog(leaving?.isOwner == true ? "Delete this group for everyone?" : "Leave this group?",
                            isPresented: Binding(get: { leaving != nil }, set: { if !$0 { leaving = nil } }),
                            titleVisibility: .visible) {
            Button(leaving?.isOwner == true ? "Delete group" : "Leave group", role: .destructive) {
                if let group = leaving { Task { await sync.leave(group) } }
                leaving = nil
            }
        }
        .sheet(item: $sharing) { item in
            CloudSharingSheet(share: item.share, container: sync.cloudContainer)
                .ignoresSafeArea()
        }
        .task { await sync.refresh() }
        .overlay { if sync.isLoading && sync.groups.isEmpty { ProgressView() } }
    }

    private var intro: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.3.fill")
                .font(.title2)
                .foregroundStyle(Palette.highlight)
                .frame(width: 52, height: 52)
                .glassEffect(.regular.tint(Palette.glow.opacity(0.5)), in: .circle)
            Text("Encourage each other. Groups are private: only people you invite can see them, and you choose what you share.")
                .font(.subheadline)
        }
        .padding(16)
        .surface(cornerRadius: 22)
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What you share").sectionLabelStyle()
            TextField("Your name in groups", text: Binding(get: { sync.displayName }, set: { sync.displayName = $0 }))
                .textInputAutocapitalization(.words)
                .padding(12)
                .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 12))
                .onSubmit { sync.publishSoon() }
            Toggle("Prayers (how many of 5 today, streak)", isOn: Binding(get: { sync.sharePrayers }, set: { sync.sharePrayers = $0 }))
            Toggle("Qur'an (ayat today and this week, goal, streak)", isOn: Binding(get: { sync.shareQuran }, set: { sync.shareQuran = $0 }))
            Text("Only totals are shared, never which prayer, reasons or notes. Everything travels through iCloud sharing; Niyat has no servers.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .padding(18)
        .surface(cornerRadius: 22)
    }
}

private struct GroupCard: View {
    let group: AccountabilityGroup
    let onInvite: () -> Void
    let onLeave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(group.name).font(.title3.weight(.bold))
                Spacer()
                Menu {
                    if group.isOwner {
                        Button("Invite people", systemImage: "person.badge.plus", action: onInvite)
                    }
                    Button(group.isOwner ? "Delete group" : "Leave group", systemImage: "rectangle.portrait.and.arrow.right",
                           role: .destructive, action: onLeave)
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3)
                }
            }
            ForEach(group.members) { member in
                MemberRow(member: member)
            }
            if group.members.count <= 1, group.isOwner {
                Button(action: onInvite) {
                    Label("Invite people", systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(18)
        .glassPanel(cornerRadius: 26, tint: Palette.glow.opacity(0.25))
    }
}

private struct MemberRow: View {
    let member: AccountabilityGroup.Member

    var body: some View {
        let s = member.snapshot
        HStack(spacing: 12) {
            Text(String(s.displayName.prefix(1)).uppercased())
                .font(.headline)
                .foregroundStyle(.black)
                .frame(width: 38, height: 38)
                .background(member.isMe ? Palette.highlight : Palette.accent, in: .circle)
            VStack(alignment: .leading, spacing: 4) {
                Text(member.isMe ? "\(s.displayName) (you)" : s.displayName).font(.subheadline.weight(.semibold))
                HStack(spacing: 12) {
                    if s.prayersToday >= 0 {
                        Label("\(s.prayersToday)/5", systemImage: "sun.horizon.fill")
                    }
                    if s.quranToday >= 0 {
                        Label("\(s.quranToday) ayat", systemImage: "book.fill")
                    }
                    if s.quranGoalComplete {
                        Label("Goal", systemImage: "checkmark.seal.fill").foregroundStyle(Palette.highlight)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            let streak = max(s.prayerStreak, s.quranStreak)
            if streak > 0 {
                Label("\(streak)", systemImage: "flame.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.highlight)
                    .accessibilityLabel("\(streak) day streak")
            }
        }
        .padding(10)
        .surface(cornerRadius: 16)
    }
}

/// Apple's standard invite sheet (Messages, Mail, copy link, who can join).
private struct CloudSharingSheet: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}
}

/// Receives group invitations tapped in Messages or Mail.
final class GroupsSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor in await GroupSync.shared.accept(metadata) }
    }
}

final class GroupsAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = GroupsSceneDelegate.self
        return configuration
    }
}

#else

/// Shown in the free build: Groups needs iCloud sharing (paid developer account).
struct GroupsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Palette.highlight)
                    .frame(width: 90, height: 90)
                    .glassEffect(.regular.tint(Palette.glow.opacity(0.5)), in: .circle)
                Text("Groups").font(.title.weight(.bold))
                Text("Private accountability circles with family and friends: see each other's prayers and Qur'an progress and encourage one another.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Label("Groups use iCloud sharing, which Apple only allows with a paid developer account. Build with `make full` to turn it on.",
                      systemImage: "lock.slash")
                    .font(.footnote)
                    .padding(16)
                    .surface(cornerRadius: 18)
            }
            .padding(24)
        }
        .niyatBackground()
        .navigationTitle("Groups")
    }
}

#endif
