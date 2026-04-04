import AppKit
import SwiftUI

/// SwiftUI view that renders a DiffPanel with VSCode-style diff highlighting.
struct DiffPanelView: View {
    @ObservedObject var panel: DiffPanel
    let isFocused: Bool
    let isVisibleInUI: Bool
    let portalPriority: Int
    let onRequestPanelFocus: () -> Void

    @State private var focusFlashOpacity: Double = 0.0
    @State private var focusFlashAnimationGeneration: Int = 0
    @State private var viewMode: DiffViewMode = .unified
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if panel.isFileUnavailable {
                fileUnavailableView
            } else if panel.parsedDiff.isEmpty {
                noDiffView
            } else {
                diffContentView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundColor)
        .overlay {
            RoundedRectangle(cornerRadius: FocusFlashPattern.ringCornerRadius)
                .stroke(cmuxAccentColor().opacity(focusFlashOpacity), lineWidth: 3)
                .shadow(color: cmuxAccentColor().opacity(focusFlashOpacity * 0.35), radius: 10)
                .padding(FocusFlashPattern.ringInset)
                .allowsHitTesting(false)
        }
        .overlay {
            if isVisibleInUI {
                DiffPointerObserver(onPointerDown: onRequestPanelFocus)
            }
        }
        .onChange(of: panel.focusFlashToken) { _ in
            triggerFocusFlashAnimation()
        }
    }

    // MARK: - Diff Content

    private var diffContentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header with stats and view mode toggle
                diffHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                Divider()
                    .padding(.horizontal, 16)

                // File entries
                ForEach(panel.parsedDiff.files) { file in
                    fileEntryView(file)
                }
            }
        }
    }

    private var diffHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.badge.plus")
                .foregroundColor(.secondary)
                .font(.system(size: 12))

            if !panel.filePath.isEmpty {
                Text(panel.filePath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Stats
            let diff = panel.parsedDiff
            HStack(spacing: 6) {
                if diff.totalAdditions > 0 {
                    Text("+\(diff.totalAdditions)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(additionTextColor)
                }
                if diff.totalDeletions > 0 {
                    Text("-\(diff.totalDeletions)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(deletionTextColor)
                }
            }

            // View mode picker
            Picker("", selection: $viewMode) {
                Text(String(localized: "diff.viewMode.unified", defaultValue: "Unified"))
                    .tag(DiffViewMode.unified)
                Text(String(localized: "diff.viewMode.sideBySide", defaultValue: "Side by Side"))
                    .tag(DiffViewMode.sideBySide)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
        }
    }

    @ViewBuilder
    private func fileEntryView(_ file: DiffFileEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // File path header
            filePathBar(for: file)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            // Hunks
            switch viewMode {
            case .unified:
                unifiedDiffView(for: file)
            case .sideBySide:
                sideBySideDiffView(for: file)
            }
        }
    }

    private func filePathBar(for file: DiffFileEntry) -> some View {
        HStack(spacing: 6) {
            Image(systemName: fileStatusIcon(for: file))
                .foregroundColor(fileStatusColor(for: file))
                .font(.system(size: 11))

            Text(file.displayPath)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)

            Spacer()

            HStack(spacing: 4) {
                if file.additionCount > 0 {
                    Text("+\(file.additionCount)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(additionTextColor)
                }
                if file.deletionCount > 0 {
                    Text("-\(file.deletionCount)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(deletionTextColor)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(fileHeaderBackground)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Unified Diff View

    private func unifiedDiffView(for file: DiffFileEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(file.hunks) { hunk in
                ForEach(hunk.lines) { line in
                    unifiedLineView(line)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private func unifiedLineView(_ line: DiffLine) -> some View {
        HStack(spacing: 0) {
            // Line numbers
            HStack(spacing: 0) {
                Text(line.oldLineNumber.map { String($0) } ?? "")
                    .frame(width: 40, alignment: .trailing)
                Text(line.newLineNumber.map { String($0) } ?? "")
                    .frame(width: 40, alignment: .trailing)
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(lineNumberColor)
            .padding(.trailing, 8)

            // Prefix indicator
            Text(linePrefix(for: line.type))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(lineTextColor(for: line.type))
                .frame(width: 14, alignment: .leading)

            // Line content
            Text(line.text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(lineTextColor(for: line.type))
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 0.5)
        .padding(.horizontal, 4)
        .background(lineBackground(for: line.type))
    }

    // MARK: - Side-by-Side View

    private func sideBySideDiffView(for file: DiffFileEntry) -> some View {
        let sidePairs = buildSideBySidePairs(file: file)

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sidePairs.enumerated()), id: \.offset) { _, pair in
                HStack(spacing: 1) {
                    // Left side (old)
                    sideLineView(
                        lineNumber: pair.oldLineNumber,
                        text: pair.oldText,
                        type: pair.oldType
                    )

                    // Divider
                    Rectangle()
                        .fill(dividerColor)
                        .frame(width: 1)

                    // Right side (new)
                    sideLineView(
                        lineNumber: pair.newLineNumber,
                        text: pair.newText,
                        type: pair.newType
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private func sideLineView(lineNumber: Int?, text: String?, type: DiffLineType?) -> some View {
        HStack(spacing: 0) {
            Text(lineNumber.map { String($0) } ?? "")
                .frame(width: 36, alignment: .trailing)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(lineNumberColor)
                .padding(.trailing, 6)

            Text(text ?? "")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(type.map { lineTextColor(for: $0) } ?? .clear)
                .textSelection(.enabled)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 0.5)
        .padding(.horizontal, 4)
        .background(type.map { lineBackground(for: $0) } ?? Color.clear)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Side-by-Side Pairing

    private struct SidePair {
        var oldLineNumber: Int?
        var oldText: String?
        var oldType: DiffLineType?
        var newLineNumber: Int?
        var newText: String?
        var newType: DiffLineType?
    }

    private func buildSideBySidePairs(file: DiffFileEntry) -> [SidePair] {
        var pairs: [SidePair] = []

        for hunk in file.hunks {
            // Add hunk header as a full-width row
            if let headerLine = hunk.lines.first(where: { $0.type == .hunkHeader }) {
                pairs.append(SidePair(
                    oldText: headerLine.text, oldType: .hunkHeader,
                    newText: headerLine.text, newType: .hunkHeader
                ))
            }

            // Collect consecutive deletions and additions to pair them
            var deletions: [DiffLine] = []
            var additions: [DiffLine] = []

            func flushPending() {
                let maxCount = max(deletions.count, additions.count)
                for i in 0..<maxCount {
                    var pair = SidePair()
                    if i < deletions.count {
                        pair.oldLineNumber = deletions[i].oldLineNumber
                        pair.oldText = deletions[i].text
                        pair.oldType = .deletion
                    }
                    if i < additions.count {
                        pair.newLineNumber = additions[i].newLineNumber
                        pair.newText = additions[i].text
                        pair.newType = .addition
                    }
                    pairs.append(pair)
                }
                deletions.removeAll()
                additions.removeAll()
            }

            for line in hunk.lines where line.type != .hunkHeader {
                switch line.type {
                case .deletion:
                    if !additions.isEmpty {
                        flushPending()
                    }
                    deletions.append(line)
                case .addition:
                    additions.append(line)
                case .context:
                    flushPending()
                    pairs.append(SidePair(
                        oldLineNumber: line.oldLineNumber,
                        oldText: line.text,
                        oldType: .context,
                        newLineNumber: line.newLineNumber,
                        newText: line.text,
                        newType: .context
                    ))
                default:
                    break
                }
            }
            flushPending()
        }

        return pairs
    }

    // MARK: - Empty States

    private var noDiffView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(String(localized: "diff.noDiff.title", defaultValue: "No changes"))
                .font(.headline)
                .foregroundColor(.primary)
            if !panel.filePath.isEmpty {
                Text(panel.filePath)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }
            Text(String(localized: "diff.noDiff.message", defaultValue: "The file has no uncommitted changes."))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fileUnavailableView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(String(localized: "diff.fileUnavailable.title", defaultValue: "File unavailable"))
                .font(.headline)
                .foregroundColor(.primary)
            Text(panel.filePath)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
            Text(String(localized: "diff.fileUnavailable.message", defaultValue: "The file may have been moved or deleted."))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Colors

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(white: 0.12, alpha: 1.0))
            : Color(nsColor: NSColor(white: 0.98, alpha: 1.0))
    }

    private var fileHeaderBackground: Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(white: 0.16, alpha: 1.0))
            : Color(nsColor: NSColor(white: 0.94, alpha: 1.0))
    }

    private var lineNumberColor: Color {
        colorScheme == .dark
            ? Color(white: 0.4)
            : Color(white: 0.6)
    }

    private var dividerColor: Color {
        colorScheme == .dark
            ? Color(white: 0.25)
            : Color(white: 0.8)
    }

    private var additionTextColor: Color {
        colorScheme == .dark
            ? Color(red: 0.4, green: 0.85, blue: 0.4)
            : Color(red: 0.15, green: 0.55, blue: 0.15)
    }

    private var deletionTextColor: Color {
        colorScheme == .dark
            ? Color(red: 0.95, green: 0.4, blue: 0.4)
            : Color(red: 0.7, green: 0.15, blue: 0.15)
    }

    private func lineTextColor(for type: DiffLineType) -> Color {
        switch type {
        case .addition: return additionTextColor
        case .deletion: return deletionTextColor
        case .hunkHeader:
            return colorScheme == .dark
                ? Color(red: 0.5, green: 0.6, blue: 0.9)
                : Color(red: 0.3, green: 0.3, blue: 0.7)
        case .context, .fileHeader:
            return colorScheme == .dark
                ? Color(white: 0.8)
                : Color(white: 0.2)
        }
    }

    private func lineBackground(for type: DiffLineType) -> Color {
        switch type {
        case .addition:
            return colorScheme == .dark
                ? Color(red: 0.15, green: 0.3, blue: 0.15, opacity: 0.4)
                : Color(red: 0.85, green: 0.95, blue: 0.85)
        case .deletion:
            return colorScheme == .dark
                ? Color(red: 0.35, green: 0.15, blue: 0.15, opacity: 0.4)
                : Color(red: 0.95, green: 0.87, blue: 0.87)
        case .hunkHeader:
            return colorScheme == .dark
                ? Color(red: 0.15, green: 0.17, blue: 0.25, opacity: 0.5)
                : Color(red: 0.9, green: 0.92, blue: 0.97)
        case .context, .fileHeader:
            return Color.clear
        }
    }

    private func linePrefix(for type: DiffLineType) -> String {
        switch type {
        case .addition: return "+"
        case .deletion: return "-"
        case .hunkHeader: return ""
        case .context, .fileHeader: return " "
        }
    }

    private func fileStatusIcon(for file: DiffFileEntry) -> String {
        if file.isNewFile { return "plus.circle.fill" }
        if file.isDeletedFile { return "minus.circle.fill" }
        return "pencil.circle.fill"
    }

    private func fileStatusColor(for file: DiffFileEntry) -> Color {
        if file.isNewFile { return additionTextColor }
        if file.isDeletedFile { return deletionTextColor }
        return colorScheme == .dark
            ? Color(red: 0.9, green: 0.75, blue: 0.3)
            : Color(red: 0.7, green: 0.5, blue: 0.1)
    }

    // MARK: - Focus Flash

    private func triggerFocusFlashAnimation() {
        focusFlashAnimationGeneration &+= 1
        let generation = focusFlashAnimationGeneration
        focusFlashOpacity = FocusFlashPattern.values.first ?? 0

        for segment in FocusFlashPattern.segments {
            DispatchQueue.main.asyncAfter(deadline: .now() + segment.delay) {
                guard focusFlashAnimationGeneration == generation else { return }
                withAnimation(focusFlashAnimation(for: segment.curve, duration: segment.duration)) {
                    focusFlashOpacity = segment.targetOpacity
                }
            }
        }
    }

    private func focusFlashAnimation(for curve: FocusFlashCurve, duration: TimeInterval) -> Animation {
        switch curve {
        case .easeIn:
            return .easeIn(duration: duration)
        case .easeOut:
            return .easeOut(duration: duration)
        }
    }
}

// MARK: - View Mode

enum DiffViewMode: String {
    case unified
    case sideBySide
}

// MARK: - Pointer Observer (same pattern as MarkdownPanel)

private struct DiffPointerObserver: NSViewRepresentable {
    let onPointerDown: () -> Void

    func makeNSView(context: Context) -> DiffPanelPointerObserverView {
        let view = DiffPanelPointerObserverView()
        view.onPointerDown = onPointerDown
        return view
    }

    func updateNSView(_ nsView: DiffPanelPointerObserverView, context: Context) {
        nsView.onPointerDown = onPointerDown
    }
}

final class DiffPanelPointerObserverView: NSView {
    var onPointerDown: (() -> Void)?
    private var eventMonitor: Any?
    private weak var forwardedMouseTarget: NSView?

    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installEventMonitorIfNeeded()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard PaneFirstClickFocusSettings.isEnabled(),
              window?.isKeyWindow != true,
              bounds.contains(point) else { return nil }
        return self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        PaneFirstClickFocusSettings.isEnabled()
    }

    override func mouseDown(with event: NSEvent) {
        onPointerDown?()
        forwardedMouseTarget = forwardedTarget(for: event)
        forwardedMouseTarget?.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        forwardedMouseTarget?.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        forwardedMouseTarget?.mouseUp(with: event)
        forwardedMouseTarget = nil
    }

    func shouldHandle(_ event: NSEvent) -> Bool {
        guard event.type == .leftMouseDown,
              let window,
              event.window === window,
              !isHiddenOrHasHiddenAncestor else { return false }
        if PaneFirstClickFocusSettings.isEnabled(), window.isKeyWindow != true {
            return false
        }
        let point = convert(event.locationInWindow, from: nil)
        return bounds.contains(point)
    }

    func handleEventIfNeeded(_ event: NSEvent) -> NSEvent {
        guard shouldHandle(event) else { return event }
        DispatchQueue.main.async { [weak self] in
            self?.onPointerDown?()
        }
        return event
    }

    private func installEventMonitorIfNeeded() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.handleEventIfNeeded(event) ?? event
        }
    }

    private func forwardedTarget(for event: NSEvent) -> NSView? {
        guard let window else { return nil }
        guard let contentView = window.contentView else { return nil }
        isHidden = true
        defer { isHidden = false }
        let point = contentView.convert(event.locationInWindow, from: nil)
        let target = contentView.hitTest(point)
        return target === self ? nil : target
    }
}
