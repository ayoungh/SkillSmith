import Foundation

struct GitDiffService {
    private let shell = ShellCommandService()

    func checkForUpdates(skill: SkillRecord) async throws -> UpdatePreview {
        guard let upstream = skill.upstream else {
            return UpdatePreview(
                status: .unavailable,
                summary: "Link an upstream repository to check for updates.",
                localRevision: nil,
                remoteRevision: nil,
                changedFiles: [],
                diffText: "",
                checkedAt: .now
            )
        }

        let remoteURL = repositoryURL(from: upstream.repo)
        let ref = upstream.ref.isEmpty ? "main" : upstream.ref
        let lsRemote = try await shell.run(
            "/usr/bin/git",
            arguments: ["ls-remote", remoteURL, ref],
            allowNonZeroExit: true
        )

        guard let remoteRevision = lsRemote.stdout.split(separator: "\n").first?.split(separator: "\t").first.map(String.init) else {
            return UpdatePreview(
                status: .unavailable,
                summary: "Could not resolve remote revision.\n\(lsRemote.stderr)",
                localRevision: upstream.trackedRevision,
                remoteRevision: nil,
                changedFiles: [],
                diffText: lsRemote.stderr,
                checkedAt: .now
            )
        }

        let comparisonPath = skill.comparisonPath
        guard !comparisonPath.isEmpty else {
            return UpdatePreview(
                status: .unavailable,
                summary: "No local skill path available for diffing.",
                localRevision: upstream.trackedRevision,
                remoteRevision: remoteRevision,
                changedFiles: [],
                diffText: "",
                checkedAt: .now
            )
        }

        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let clone = try await shell.run(
            "/usr/bin/git",
            arguments: ["clone", "--depth", "1", "--filter=blob:none", "--sparse", "--branch", ref, remoteURL, tempRoot.path],
            allowNonZeroExit: true
        )

        guard clone.exitCode == 0 else {
            return UpdatePreview(
                status: .unavailable,
                summary: "Unable to clone upstream for diff preview.",
                localRevision: upstream.trackedRevision,
                remoteRevision: remoteRevision,
                changedFiles: [],
                diffText: clone.stderr,
                checkedAt: .now
            )
        }

        let sparse = try await shell.run(
            "/usr/bin/git",
            arguments: ["-C", tempRoot.path, "sparse-checkout", "set", upstream.path],
            allowNonZeroExit: true
        )
        guard sparse.exitCode == 0 else {
            return UpdatePreview(
                status: .unavailable,
                summary: "Unable to load the upstream subtree.",
                localRevision: upstream.trackedRevision,
                remoteRevision: remoteRevision,
                changedFiles: [],
                diffText: sparse.stderr,
                checkedAt: .now
            )
        }

        let remotePath = tempRoot.appendingPathComponent(upstream.path)
        guard FileManager.default.fileExists(atPath: remotePath.path) else {
            return UpdatePreview(
                status: .deletedUpstream,
                summary: "This skill path no longer exists upstream.",
                localRevision: upstream.trackedRevision,
                remoteRevision: remoteRevision,
                changedFiles: [],
                diffText: "",
                checkedAt: .now
            )
        }

        let diff = try await shell.run(
            "/usr/bin/git",
            arguments: ["diff", "--no-index", "--relative", comparisonPath, remotePath.path],
            allowNonZeroExit: true
        )

        let status: UpdateStatus = diff.exitCode == 0 ? .noChanges : .changesAvailable
        let diffText = diff.stdout.isEmpty ? diff.stderr : diff.stdout
        return UpdatePreview(
            status: status,
            summary: status == .noChanges ? "No upstream changes detected." : summarize(diffText: diffText, remoteRevision: remoteRevision),
            localRevision: upstream.trackedRevision,
            remoteRevision: remoteRevision,
            changedFiles: parseDiffFiles(from: diffText),
            diffText: diffText,
            checkedAt: .now
        )
    }

    private func repositoryURL(from repo: String) -> String {
        if repo.hasPrefix("http://") || repo.hasPrefix("https://") || repo.hasPrefix("git@") {
            return repo.hasSuffix(".git") ? repo : repo + ".git"
        }
        return "https://github.com/\(repo).git"
    }

    private func summarize(diffText: String, remoteRevision: String) -> String {
        let files = parseDiffFiles(from: diffText).map(\.path)
        let shortRevision = String(remoteRevision.prefix(7))
        if files.isEmpty {
            return "Changes available at \(shortRevision)."
        }
        return "Changes available at \(shortRevision): \(files.prefix(4).joined(separator: ", "))"
    }

    private func parseDiffFiles(from diffText: String) -> [DiffFile] {
        var files: [DiffFile] = []
        let chunks = diffText.components(separatedBy: "\ndiff --git ").filter { !$0.isEmpty }

        for chunk in chunks {
            let normalized = chunk.hasPrefix("diff --git ") ? chunk : "diff --git " + chunk
            guard let firstLine = normalized.split(separator: "\n").first else { continue }
            let path = firstLine
                .replacingOccurrences(of: "diff --git a/", with: "")
                .split(separator: " ")
                .first
                .map(String.init) ?? "Unknown"

            files.append(DiffFile(path: path, status: "modified", patch: normalized))
        }

        return files
    }
}
