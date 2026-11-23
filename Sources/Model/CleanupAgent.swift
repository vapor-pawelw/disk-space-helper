import Foundation

enum CleanupAgent: String, CaseIterable, Identifiable, Sendable {
    case claude, codex

    var id: Self { self }

    var name: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    var defaultModel: String {
        switch self {
        case .claude: "claude-opus-5-5"
        case .codex: "gpt-6.2-sol"
        }
    }

    var loginCommand: String {
        switch self {
        case .claude: "claude auth login"
        case .codex: "codex login"
        }
    }
}

struct CleanupAgentConfiguration: Equatable, Sendable {
    let agent: CleanupAgent
    let model: String
    let executablePath: String
}

enum CleanupScanError: Error, Equatable {
    case notInstalled
    case incompatibleCLI
    case loggedOut
    case rateLimited
    case modelUnavailable
    case timedOut
    case invalidResponse
    case scanFailed
    case fileUseUnavailable

    var retryable: Bool {
        switch self {
        case .notInstalled, .incompatibleCLI, .loggedOut, .modelUnavailable: false
        default: true
        }
    }

    func retryDelay(after attempt: Int) -> Duration {
        .seconds((self == .rateLimited ? 15 : 4) * attempt)
    }

    func message(for agent: CleanupAgent) -> String {
        switch self {
        case .notInstalled:
            String(localized: .Cleanup.cliMissing(agent.name))
        case .incompatibleCLI:
            String(localized: .Cleanup.cliIncompatible(agent.name))
        case .loggedOut:
            String(localized: .Cleanup.cliLoggedOut(agent.loginCommand))
        case .rateLimited:
            String(localized: .Cleanup.cliRateLimited(agent.name))
        case .modelUnavailable:
            String(localized: .Cleanup.modelUnavailable)
        case .timedOut:
            String(localized: .Cleanup.cliTimedOut(agent.name))
        case .invalidResponse:
            String(localized: .Cleanup.cliInvalidResponse(agent.name))
        case .fileUseUnavailable:
            String(localized: .Cleanup.fileUseUnavailable)
        case .scanFailed:
            String(localized: .Cleanup.scanFailed)
        }
    }
}
