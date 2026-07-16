import SwiftUI

struct SkillsHomeView: View {
    @Bindable var store: SkillSmithStore
    var onOpenSkill: (SkillRecord) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(sectionTitle)
                    .font(.largeTitle.bold())

                actionCards
                summaryLine
                skillSection
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sectionTitle: String {
        store.selectedSection?.rawValue ?? "All Skills"
    }

    private var actionCards: some View {
        HStack(spacing: 12) {
            ActionCard(title: "Browse skills.sh", systemImage: "magnifyingglass") {
                store.addFromSkillsShPresented = true
            }
            ActionCard(title: "New Skill", systemImage: "plus.circle.fill") {
                store.createSheetPresented = true
            }
            ActionCard(title: "Update All", systemImage: "arrow.trianglehead.2.clockwise") {
                Task { await store.updateAllSkillsShSkills() }
            }
        }
    }

    private var summaryLine: some View {
        Text(summaryText)
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private var summaryText: String {
        let total = store.skills.count
        var counts: [String: Int] = [:]
        for skill in store.skills {
            for rootName in Set(skill.installedTargets.map(\.rootName)) {
                counts[rootName, default: 0] += 1
            }
        }
        let breakdown = counts
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { "\($0.value) in \($0.key)" }
            .joined(separator: " · ")
        let updates = store.skills.filter(\.hasUpdate).count
        var text = "\(total) skills discovered"
        if !breakdown.isEmpty { text += " · \(breakdown)" }
        if updates > 0 { text += " · \(updates) with updates" }
        return text
    }

    private var skillSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.subheadline)
                Text(sectionTitle)
                    .font(.headline)
                Text("\(store.filteredSkills.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 6)

            if store.filteredSkills.isEmpty {
                ContentUnavailableView(
                    "No Skills Found",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text("Refresh discovery, adjust the search, or pull skills from skills.sh.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                VStack(spacing: 8) {
                    ForEach(store.filteredSkills) { skill in
                        SkillRowCard(skill: skill) {
                            onOpenSkill(skill)
                        }
                    }
                }
            }
        }
    }
}

private struct ActionCard: View {
    var title: String
    var systemImage: String
    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18)
                Text(title)
                    .font(.callout.weight(.medium))
                Spacer(minLength: 12)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct SkillRowCard: View {
    var skill: SkillRecord
    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "bolt.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(skill.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(skill.description.isEmpty ? "—" : skill.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                ForEach(rootNames, id: \.self) { rootName in
                    Text(rootName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quinary, in: Capsule())
                }

                if skill.hasUpdate {
                    Text("Update")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var rootNames: [String] {
        Array(Set(skill.installedTargets.map(\.rootName))).sorted()
    }
}
