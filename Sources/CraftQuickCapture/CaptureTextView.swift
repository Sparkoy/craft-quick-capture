import AppKit
import SwiftUI

/// NSTextView-backed editor that NEVER participates in drag-and-drop.
/// SwiftUI's TextEditor re-registers its text view for file drags whenever
/// focus changes, swallowing image drops and inserting the file PATH as text.
/// Overriding updateDragTypeRegistration is the one hook AppKit always calls
/// when it tries to (re)register — so registration simply never happens, and
/// drops fall through to the container's .onDrop image handler.
struct CaptureTextView: NSViewRepresentable {
    @Binding var text: String
    var focusTick: Int
    var onHeightChange: (CGFloat) -> Void

    final class NoDropTextView: NSTextView {
        override func updateDragTypeRegistration() {
            unregisterDraggedTypes()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CaptureTextView
        var lastFocusTick = -1
        init(_ parent: CaptureTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            reportHeight(tv)
        }

        func reportHeight(_ tv: NSTextView) {
            guard let container = tv.textContainer, let manager = tv.layoutManager else { return }
            manager.ensureLayout(for: container)
            let height = manager.usedRect(for: container).height
            DispatchQueue.main.async { self.parent.onHeightChange(height) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = NoDropTextView()
        tv.delegate = context.coordinator
        tv.font = .systemFont(ofSize: 15)
        tv.textColor = NSColor.white.withAlphaComponent(0.92)
        tv.insertionPointColor = NSColor(red: 0.48, green: 0.43, blue: 0.94, alpha: 1)
        tv.drawsBackground = false
        tv.isRichText = false
        tv.allowsUndo = true
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = true

        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text {
            tv.string = text
            context.coordinator.reportHeight(tv)
        }
        if context.coordinator.lastFocusTick != focusTick {
            context.coordinator.lastFocusTick = focusTick
            DispatchQueue.main.async {
                tv.window?.makeFirstResponder(tv)
            }
        }
    }
}
