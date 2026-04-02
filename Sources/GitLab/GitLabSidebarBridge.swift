import Foundation

@MainActor
final class GitLabSidebarBridge {
    static let shared = GitLabSidebarBridge()

    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 30.0
    private var config: GitLabConfig?
    private var token: String?

    private init() {}

    func start() {
        guard let config = GitLabConfig.load(),
              let token = config.loadToken() else { return }

        self.config = config
        self.token = token

        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollAllWorkspaces()
            }
        }
        // Initial poll
        Task { pollAllWorkspaces() }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pollAllWorkspaces() {
        guard let config = self.config, let token = self.token else { return }

        // TODO: Wire to actual workspace list via TerminalController or TabManager
        // For now this is a placeholder. When wired, iterate workspaces and call
        // pollMRForWorkspace(workspace:config:token:) for each.
    }

    func pollMRForWorkspace(
        workspace: Workspace,
        gitlabProject: String,
        config: GitLabConfig,
        token: String
    ) {
        guard let branch = workspace.gitBranch?.branch else {
            workspace.gitlabMRStatus = nil
            return
        }

        let encodedProject = gitlabProject.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? gitlabProject
        let urlString = "\(config.host)/api/v4/projects/\(encodedProject)/merge_requests?source_branch=\(branch)&state=opened&per_page=1"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        request.timeoutInterval = 10

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    return
                }

                let mrs = try JSONDecoder().decode([GitLabMRAPIResponse].self, from: data)
                if let mr = mrs.first {
                    workspace.gitlabMRStatus = GitLabMRStatus(
                        iid: mr.iid,
                        status: GitLabMRStatus.GitLabMRStatusType(rawValue: mr.state) ?? .open,
                        pipelineStatus: mr.headPipeline?.status.flatMap {
                            GitLabMRStatus.GitLabPipelineStatusType(rawValue: $0)
                        }
                    )
                } else {
                    workspace.gitlabMRStatus = nil
                }
            } catch {
                // Silently fail — sidebar just won't show MR status
            }
        }
    }
}

// MARK: - GitLab API Response Models

private struct GitLabMRAPIResponse: Decodable {
    let iid: Int
    let state: String
    let headPipeline: HeadPipeline?

    enum CodingKeys: String, CodingKey {
        case iid
        case state
        case headPipeline = "head_pipeline"
    }

    struct HeadPipeline: Decodable {
        let status: String?
    }
}
