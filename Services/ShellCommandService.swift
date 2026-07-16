import Foundation

struct ShellCommandService {
    /// PATH for spawned commands, resolved once. GUI apps launched from Finder
    /// inherit a minimal PATH that misses nvm/homebrew-installed tools like
    /// npx, and nvm only initializes in interactive shells, so the login-shell
    /// PATH is augmented with directly discovered tool directories.
    private static let loginShellPATH: String = {
        let home = NSHomeDirectory()
        var directories: [String] = []

        // Newest nvm-installed node, since nvm.sh isn't loaded in login shells.
        let nvmNodeRoot = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmNodeRoot) {
            let newest = versions
                .filter { $0.hasPrefix("v") }
                .max { lhs, rhs in
                    lhs.compare(rhs, options: .numeric) == .orderedAscending
                }
            if let newest {
                directories.append("\(nvmNodeRoot)/\(newest)/bin")
            }
        }

        directories.append(contentsOf: [
            "\(home)/Library/pnpm",
            "\(home)/.bun/bin",
            "\(home)/.volta/bin",
            "\(home)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin"
        ])

        directories.append(loginShellReportedPATH ?? (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"))

        let existing = directories.filter { $0.contains(":") || FileManager.default.fileExists(atPath: $0) }
        return existing.joined(separator: ":")
    }()

    private static var loginShellReportedPATH: String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "printf %s \"$PATH\""]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return process.terminationStatus == 0 && !path.isEmpty ? path : nil
    }

    func run(
        _ launchPath: String,
        arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil,
        allowNonZeroExit: Bool = false
    ) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectory

            var mergedEnvironment = ProcessInfo.processInfo.environment
            mergedEnvironment["PATH"] = Self.loginShellPATH
            for (key, value) in environment ?? [:] {
                mergedEnvironment[key] = value
            }
            process.environment = mergedEnvironment

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            final class DataBox: @unchecked Sendable { var data = Data() }
            let stdoutBox = DataBox()
            let stderrBox = DataBox()
            let drained = DispatchGroup()
            drained.enter()
            drained.enter()

            process.terminationHandler = { process in
                drained.notify(queue: .global(qos: .userInitiated)) {
                    let result = CommandResult(
                        launchPath: launchPath,
                        arguments: arguments,
                        exitCode: process.terminationStatus,
                        stdout: String(decoding: stdoutBox.data, as: UTF8.self),
                        stderr: String(decoding: stderrBox.data, as: UTF8.self)
                    )

                    if !allowNonZeroExit && process.terminationStatus != 0 {
                        continuation.resume(throwing: NSError(
                            domain: "SkillSmith.ShellCommandService",
                            code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: result.stderr.isEmpty ? result.stdout : result.stderr]
                        ))
                    } else {
                        continuation.resume(returning: result)
                    }
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                stdoutBox.data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                drained.leave()
            }
            DispatchQueue.global(qos: .userInitiated).async {
                stderrBox.data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                drained.leave()
            }
        }
    }
}
