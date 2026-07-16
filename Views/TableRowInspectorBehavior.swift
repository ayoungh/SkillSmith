import AppKit
import SwiftUI

private final class TableRowClickMonitorView: NSView {
    var selectedItemCount = 0
    var isInspectorPresented = false
    var onClickSelectedRow: (() -> Void)?

    private var eventMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()

        guard window != nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.inspect(event)
            return event
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func stopMonitoring() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func inspect(_ event: NSEvent) {
        guard selectedItemCount == 1, isInspectorPresented,
              let window, event.window === window,
              bounds.contains(convert(event.locationInWindow, from: nil)),
              let contentView = window.contentView
        else { return }

        let contentPoint = contentView.convert(event.locationInWindow, from: nil)
        guard let hitView = contentView.hitTest(contentPoint),
              let tableView = hitView.firstSuperview(of: NSTableView.self)
        else { return }

        let tablePoint = tableView.convert(event.locationInWindow, from: nil)
        let clickedRow = tableView.row(at: tablePoint)
        guard clickedRow >= 0,
              tableView.selectedRowIndexes.count == 1,
              tableView.selectedRow == clickedRow
        else { return }

        DispatchQueue.main.async { [weak self] in
            self?.onClickSelectedRow?()
        }
    }
}

private extension NSView {
    func firstSuperview<ViewType: NSView>(of type: ViewType.Type) -> ViewType? {
        var candidate: NSView? = self
        while let view = candidate {
            if let match = view as? ViewType { return match }
            candidate = view.superview
        }
        return nil
    }
}

private struct TableRowClickMonitor: NSViewRepresentable {
    let selectedItemCount: Int
    @Binding var isInspectorPresented: Bool

    func makeNSView(context: Context) -> TableRowClickMonitorView {
        TableRowClickMonitorView()
    }

    func updateNSView(_ nsView: TableRowClickMonitorView, context: Context) {
        nsView.selectedItemCount = selectedItemCount
        nsView.isInspectorPresented = isInspectorPresented
        nsView.onClickSelectedRow = {
            isInspectorPresented = false
        }
    }

    static func dismantleNSView(_ nsView: TableRowClickMonitorView, coordinator: ()) {
        nsView.stopMonitoring()
    }
}

private struct TableRowInspectorToggleModifier<ID: Hashable>: ViewModifier {
    @Binding var selection: Set<ID>
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.background {
            TableRowClickMonitor(
                selectedItemCount: selection.count,
                isInspectorPresented: $isPresented
            )
        }
    }
}

extension View {
    func togglesInspectorOnRowClick<ID: Hashable>(
        selection: Binding<Set<ID>>,
        isPresented: Binding<Bool>
    ) -> some View {
        modifier(TableRowInspectorToggleModifier(selection: selection, isPresented: isPresented))
    }
}
