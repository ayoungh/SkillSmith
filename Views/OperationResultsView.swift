import SwiftUI

struct OperationResultsView: View {
    var results: [OperationResult]

    var body: some View {
        if !results.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Latest Operation")
                    .font(.headline)
                ForEach(results.suffix(8)) { result in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: result.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(result.succeeded ? .green : .red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.summary)
                                .font(.callout.weight(.medium))
                            Text(result.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(result.path)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .padding(12)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
