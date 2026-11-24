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

    /// Selectable models, mirroring the lists offered in MergeTether.
    var models: [CleanupModel] {
        switch self {
        case .claude: [
            .init(id: "claude-fable-5-2", name: "Claude Fable 5.2"),
            .init(id: "claude-opus-5-5", name: "Claude Opus 5.5"),
            .init(id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5"),
        ]
        case .codex: [
            .init(id: "gpt-6.2-sol", name: "GPT-6.2 Sol"),
            .init(id: "gpt-6.1-sol", name: "GPT-6.1 Sol"),
            .init(id: "gpt-6-astra", name: "GPT-6 Astra"),
            .init(id: "gpt-6.1-terra", name: "GPT-6.1 Terra"),
            .init(id: "gpt-6-luna", name: "GPT-6 Luna"),
            .init(id: "gpt-5.6-luna", name: "GPT-5.6 Luna"),
        ]
        }
    }

    var loginCommand: String {
        switch self {
        case .claude: "claude auth login"
        case .codex: "codex login"
        }
    }
}

struct CleanupModel: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
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
