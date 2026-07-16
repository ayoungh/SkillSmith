import Foundation

struct TextDiffService {
    func diff(original: String, updated: String) -> String {
        guard original != updated else { return "No changes." }

        let oldLines = original.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = updated.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let changes = newLines.difference(from: oldLines)

        var output = ["--- current", "+++ proposed"]
        for change in changes {
            switch change {
            case let .remove(offset, element, _):
                output.append("-\(offset + 1) \(element)")
            case let .insert(offset, element, _):
                output.append("+\(offset + 1) \(element)")
            }
        }
        return output.joined(separator: "\n")
    }
}
