import Foundation
import Combine

/// Represents a single line in a unified diff.
enum DiffLineType: Equatable, Sendable {
    case context
    case addition
    case deletion
    case hunkHeader
    case fileHeader
}

/// A parsed line from a unified diff.
struct DiffLine: Identifiable, Equatable, Sendable {
    let id: Int
    let type: DiffLineType
    let text: String
    /// Line number in the old file (nil for additions/headers).
    let oldLineNumber: Int?
    /// Line number in the new file (nil for deletions/headers).
    let newLineNumber: Int?
}

/// A hunk within a diff file entry.
struct DiffHunk: Identifiable, Equatable, Sendable {
    let id: Int
    let header: String
    let lines: [DiffLine]
}

/// A single file entry in a diff (one "--- a/file ... +++ b/file" block).
struct DiffFileEntry: Identifiable, Equatable, Sendable {
    let id: Int
    let oldPath: String
    let newPath: String
    let hunks: [DiffHunk]

    var displayPath: String {
        if oldPath == "/dev/null" { return newPath }
        if newPath == "/dev/null" { return oldPath }
        return newPath
    }

    var isNewFile: Bool { oldPath == "/dev/null" }
    var isDeletedFile: Bool { newPath == "/dev/null" }

    var additionCount: Int {
        hunks.flatMap(\.lines).filter { $0.type == .addition }.count
    }

    var deletionCount: Int {
        hunks.flatMap(\.lines).filter { $0.type == .deletion }.count
    }
}

/// Parsed result of a unified diff.
struct ParsedDiff: Equatable, Sendable {
    let files: [DiffFileEntry]
    let rawText: String

    var isEmpty: Bool { files.isEmpty }

    var totalAdditions: Int { files.reduce(0) { $0 + $1.additionCount } }
    var totalDeletions: Int { files.reduce(0) { $0 + $1.deletionCount } }
}

/// A panel that displays a unified diff with syntax highlighting.
/// Supports opening .diff/.patch files or running `git diff` on a tracked file.
@MainActor
final class DiffPanel: Panel, ObservableObject {
    let id: UUID
    let panelType: PanelType = .diff

    /// The source for this diff panel.
    enum DiffSource: Equatable, Sendable {
        /// A .diff or .patch file on disk.
        case diffFile(path: String)
        /// A tracked file — we run `git diff` to get the diff.
        case gitFile(path: String)
        /// Raw diff content passed directly (e.g. piped via CLI).
        case rawContent
    }

    /// How this diff was sourced.
    let source: DiffSource

    /// Absolute path associated with this panel (for file watching).
    let filePath: String

    /// The workspace this panel belongs to.
    private(set) var workspaceId: UUID

    /// Parsed diff data.
    @Published private(set) var parsedDiff: ParsedDiff = ParsedDiff(files: [], rawText: "")

    /// Raw diff text.
    @Published private(set) var rawDiffText: String = ""

    /// Title shown in the tab bar.
    @Published private(set) var displayTitle: String = ""

    /// SF Symbol icon for the tab bar.
    var displayIcon: String? { "doc.badge.plus" }

    /// Whether the source file is unavailable.
    @Published private(set) var isFileUnavailable: Bool = false

    /// Token incremented to trigger focus flash animation.
    @Published private(set) var focusFlashToken: Int = 0

    // MARK: - File watching

    private nonisolated(unsafe) var fileWatchSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var isClosed: Bool = false
    private let watchQueue = DispatchQueue(label: "com.cmux.diff-file-watch", qos: .utility)

    private static let maxReattachAttempts = 6
    private static let reattachDelay: TimeInterval = 0.5

    // MARK: - Init

    /// Initialize with a file path. If the file is a .diff/.patch, parse it directly.
    /// Otherwise, run `git diff` on it.
    init(workspaceId: UUID, filePath: String) {
        self.id = UUID()
        self.workspaceId = workspaceId
        self.filePath = filePath

        let ext = (filePath as NSString).pathExtension.lowercased()
        if ext == "diff" || ext == "patch" {
            self.source = .diffFile(path: filePath)
            self.displayTitle = (filePath as NSString).lastPathComponent
        } else {
            self.source = .gitFile(path: filePath)
            let filename = (filePath as NSString).lastPathComponent
            self.displayTitle = "\(filename) (diff)"
        }

        loadDiffContent()
        startFileWatcher()
        if isFileUnavailable && fileWatchSource == nil {
            scheduleReattach(attempt: 1)
        }
    }

    /// Initialize with raw diff content (no file watching).
    init(workspaceId: UUID, rawContent: String, title: String) {
        self.id = UUID()
        self.workspaceId = workspaceId
        self.filePath = ""
        self.source = .rawContent
        self.displayTitle = title

        self.rawDiffText = rawContent
        self.parsedDiff = DiffParser.parse(rawContent)
    }

    // MARK: - Panel protocol

    func focus() {
        // Read-only panel; no first responder to manage.
    }

    func unfocus() {
        // No-op for read-only panel.
    }

    func close() {
        isClosed = true
        stopFileWatcher()
    }

    func triggerFlash(reason: WorkspaceAttentionFlashReason) {
        _ = reason
        guard NotificationPaneFlashSettings.isEnabled() else { return }
        focusFlashToken += 1
    }

    // MARK: - Content loading

    private func loadDiffContent() {
        switch source {
        case .diffFile(let path):
            loadDiffFile(at: path)
        case .gitFile(let path):
            loadGitDiff(for: path)
        case .rawContent:
            break
        }
    }

    private func loadDiffFile(at path: String) {
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            rawDiffText = content
            parsedDiff = DiffParser.parse(content)
            isFileUnavailable = false
        } catch {
            if let data = FileManager.default.contents(atPath: path),
               let decoded = String(data: data, encoding: .isoLatin1) {
                rawDiffText = decoded
                parsedDiff = DiffParser.parse(decoded)
                isFileUnavailable = false
            } else {
                isFileUnavailable = true
            }
        }
    }

    private func loadGitDiff(for path: String) {
        let directory = (path as NSString).deletingLastPathComponent
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["diff", "HEAD", "--", path]
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if output.isEmpty {
                // No diff — file is unchanged or untracked. Try staged diff.
                let stagedProcess = Process()
                stagedProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                stagedProcess.arguments = ["diff", "--cached", "--", path]
                stagedProcess.currentDirectoryURL = URL(fileURLWithPath: directory)
                let stagedPipe = Pipe()
                stagedProcess.standardOutput = stagedPipe
                stagedProcess.standardError = Pipe()
                try stagedProcess.run()
                stagedProcess.waitUntilExit()
                let stagedData = stagedPipe.fileHandleForReading.readDataToEndOfFile()
                let stagedOutput = String(data: stagedData, encoding: .utf8) ?? ""
                rawDiffText = stagedOutput
                parsedDiff = DiffParser.parse(stagedOutput)
            } else {
                rawDiffText = output
                parsedDiff = DiffParser.parse(output)
            }
            isFileUnavailable = false
        } catch {
            isFileUnavailable = true
        }
    }

    // MARK: - File watcher

    private func startFileWatcher() {
        guard source != .rawContent else { return }
        let watchPath: String
        switch source {
        case .diffFile(let path): watchPath = path
        case .gitFile(let path): watchPath = path
        case .rawContent: return
        }

        let fd = open(watchPath, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: watchQueue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) {
                DispatchQueue.main.async {
                    self.stopFileWatcher()
                    self.loadDiffContent()
                    if self.isFileUnavailable {
                        self.scheduleReattach(attempt: 1)
                    } else {
                        self.startFileWatcher()
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.loadDiffContent()
                }
            }
        }

        source.setCancelHandler {
            Darwin.close(fd)
        }

        source.resume()
        fileWatchSource = source
    }

    private func scheduleReattach(attempt: Int) {
        guard attempt <= Self.maxReattachAttempts else { return }
        watchQueue.asyncAfter(deadline: .now() + Self.reattachDelay) { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                guard !self.isClosed else { return }
                let checkPath: String
                switch self.source {
                case .diffFile(let path): checkPath = path
                case .gitFile(let path): checkPath = path
                case .rawContent: return
                }
                if FileManager.default.fileExists(atPath: checkPath) {
                    self.isFileUnavailable = false
                    self.loadDiffContent()
                    self.startFileWatcher()
                } else {
                    self.scheduleReattach(attempt: attempt + 1)
                }
            }
        }
    }

    private func stopFileWatcher() {
        if let source = fileWatchSource {
            source.cancel()
            fileWatchSource = nil
        }
        fileDescriptor = -1
    }

    deinit {
        fileWatchSource?.cancel()
    }
}

// MARK: - Diff Parser

enum DiffParser {
    static func parse(_ text: String) -> ParsedDiff {
        guard !text.isEmpty else {
            return ParsedDiff(files: [], rawText: text)
        }

        let lines = text.components(separatedBy: "\n")
        var files: [DiffFileEntry] = []
        var currentOldPath: String?
        var currentNewPath: String?
        var currentHunks: [DiffHunk] = []
        var currentHunkLines: [DiffLine] = []
        var currentHunkHeader: String?
        var lineId = 0
        var hunkId = 0
        var fileId = 0
        var oldLine = 0
        var newLine = 0

        func finishHunk() {
            if let header = currentHunkHeader {
                currentHunks.append(DiffHunk(id: hunkId, header: header, lines: currentHunkLines))
                hunkId += 1
                currentHunkLines = []
                currentHunkHeader = nil
            }
        }

        func finishFile() {
            finishHunk()
            if let oldPath = currentOldPath, let newPath = currentNewPath {
                files.append(DiffFileEntry(id: fileId, oldPath: oldPath, newPath: newPath, hunks: currentHunks))
                fileId += 1
            }
            currentOldPath = nil
            currentNewPath = nil
            currentHunks = []
        }

        for line in lines {
            if line.hasPrefix("diff --git ") || line.hasPrefix("diff --cc ") {
                finishFile()
                // Will be populated by --- and +++ lines
                continue
            }

            if line.hasPrefix("--- ") {
                let path = String(line.dropFirst(4))
                currentOldPath = path.hasPrefix("a/") ? String(path.dropFirst(2)) : path
                continue
            }

            if line.hasPrefix("+++ ") {
                let path = String(line.dropFirst(4))
                currentNewPath = path.hasPrefix("b/") ? String(path.dropFirst(2)) : path
                continue
            }

            if line.hasPrefix("@@ ") {
                finishHunk()
                currentHunkHeader = line
                // Parse line numbers from @@ -old,count +new,count @@
                let numbers = parseHunkHeader(line)
                oldLine = numbers.oldStart
                newLine = numbers.newStart
                currentHunkLines.append(DiffLine(
                    id: lineId, type: .hunkHeader, text: line,
                    oldLineNumber: nil, newLineNumber: nil
                ))
                lineId += 1
                continue
            }

            // Skip git binary/index/mode lines
            if line.hasPrefix("index ") || line.hasPrefix("old mode") ||
               line.hasPrefix("new mode") || line.hasPrefix("new file") ||
               line.hasPrefix("deleted file") || line.hasPrefix("similarity") ||
               line.hasPrefix("rename from") || line.hasPrefix("rename to") ||
               line.hasPrefix("Binary files") {
                continue
            }

            guard currentHunkHeader != nil else { continue }

            if line.hasPrefix("+") {
                currentHunkLines.append(DiffLine(
                    id: lineId, type: .addition, text: String(line.dropFirst()),
                    oldLineNumber: nil, newLineNumber: newLine
                ))
                newLine += 1
                lineId += 1
            } else if line.hasPrefix("-") {
                currentHunkLines.append(DiffLine(
                    id: lineId, type: .deletion, text: String(line.dropFirst()),
                    oldLineNumber: oldLine, newLineNumber: nil
                ))
                oldLine += 1
                lineId += 1
            } else if line.hasPrefix(" ") || line.isEmpty {
                let text = line.isEmpty ? "" : String(line.dropFirst())
                currentHunkLines.append(DiffLine(
                    id: lineId, type: .context, text: text,
                    oldLineNumber: oldLine, newLineNumber: newLine
                ))
                oldLine += 1
                newLine += 1
                lineId += 1
            } else if line.hasPrefix("\\") {
                // "\ No newline at end of file" — skip
                continue
            }
        }

        finishFile()
        return ParsedDiff(files: files, rawText: text)
    }

    private static func parseHunkHeader(_ header: String) -> (oldStart: Int, newStart: Int) {
        // Format: @@ -oldStart,oldCount +newStart,newCount @@ optional context
        let scanner = Scanner(string: header)
        scanner.scanString("@@")
        scanner.scanString("-")
        let oldStart = scanner.scanInt() ?? 1
        if scanner.scanString(",") != nil {
            _ = scanner.scanInt() // oldCount
        }
        scanner.scanString("+")
        let newStart = scanner.scanInt() ?? 1
        return (oldStart, newStart)
    }
}
