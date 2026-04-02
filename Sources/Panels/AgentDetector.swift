import Foundation

enum AgentType: String, Sendable, Equatable {
    case claude
    case codex
    case unknown
}

enum AgentStatus: String, Sendable, Equatable {
    case idle
    case thinking
    case editing
    case runningCommand
    case waitingForInput
}

struct AgentDetector {
    static func inferAgentType(processName: String) -> AgentType {
        let name = processName.split(separator: "/").last.map(String.init) ?? processName
        if name.contains("claude") { return .claude }
        if name.contains("codex") { return .codex }
        return .unknown
    }

    static func inferStatus(from lines: [String]) -> AgentStatus {
        let joined = lines.joined(separator: "\n")

        // Check waiting for input first (highest priority — user needs to act)
        if joined.range(of: #"\[Y/n\]"#, options: .regularExpression) != nil ||
           joined.range(of: #"\(Y\)es\s*/\s*\(N\)o"#, options: .regularExpression) != nil ||
           joined.contains("Allow?") ||
           joined.contains("approve?") ||
           joined.contains("Do you want to proceed") {
            return .waitingForInput
        }

        // Check thinking (spinner characters or "Thinking")
        let spinnerChars: [Character] = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        if let lastLine = lines.last?.trimmingCharacters(in: .whitespaces) {
            if spinnerChars.contains(where: { lastLine.hasPrefix(String($0)) }) ||
               lastLine.contains("Thinking") {
                return .thinking
            }
        }

        // Check editing (diff output)
        let hasDiffLines = lines.contains { line in
            line.hasPrefix("+ ") || line.hasPrefix("- ") || line.hasPrefix("@@ ")
        }
        if hasDiffLines { return .editing }

        // Check idle (shell prompt at last line)
        if let lastLine = lines.last?.trimmingCharacters(in: .whitespaces) {
            if lastLine.range(of: #"[❯$%#]\s*$"#, options: .regularExpression) != nil {
                return .idle
            }
        }

        // Default: running command
        return .runningCommand
    }
}
