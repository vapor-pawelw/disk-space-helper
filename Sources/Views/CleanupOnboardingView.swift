import SwiftUI

struct CleanupOnboardingFlow: View {
    let monitor: DiskMonitorService
    let onComplete: () -> Void

    var body: some View {
        if let step = monitor.settings.cleanupOnboardingStep {
            CleanupOnboardingPage(monitor: monitor, step: step) { agent in
                guard monitor.settings.finishCleanupOnboardingStep(step, enableWith: agent) else { return }
                if monitor.settings.cleanupOnboardingStep == nil { onComplete() }
            }
            .id(step)
        }
    }
}

private struct CleanupOnboardingPage: View {
    let monitor: DiskMonitorService
    let step: CleanupOnboardingStep
    let onContinue: (CleanupAgent?) -> Void

    @State private var selectedAgent: CleanupAgent
    @State private var connectionCheck: Task<Void, Never>?
    @State private var failureMessage: String?

    init(monitor: DiskMonitorService, step: CleanupOnboardingStep, onContinue: @escaping (CleanupAgent?) -> Void) {
        self.monitor = monitor
        self.step = step
        self.onContinue = onContinue
        _selectedAgent = State(initialValue: monitor.settings.cleanupAgent)
    }

    private var isRecovery: Bool { step == .quickRecovery }

    private var isEnabled: Bool {
        isRecovery ? monitor.settings.quickRecoveryEnabled : monitor.settings.cleanupEnabled
    }

    private var tint: Color { isRecovery ? .teal : .blue }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    illustration
                    title
                    agentOptions
                }
                .padding(.horizontal, 30)
                .padding(.top, 28)
                .padding(.bottom, 16)
            }

            Divider()
            actions
                .padding(.horizontal, 30)
                .padding(.vertical, 17)
        }
        .onDisappear { connectionCheck?.cancel() }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isRecovery ? .Onboarding.recoveryTitle : .Onboarding.suggestionsTitle)
                .font(.system(size: 33, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text(isRecovery ? .Onboarding.recoveryBody : .Onboarding.suggestionsBody)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var agentOptions: some View {
        if isEnabled {
            Label(.Onboarding.alreadyEnabled, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                Picker(.Onboarding.sharedAgent, selection: $selectedAgent) {
                    ForEach(CleanupAgent.allCases) { agent in
                        Text(agent.name).tag(agent)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(connectionCheck != nil)
                .onChange(of: selectedAgent) { _, _ in failureMessage = nil }

                Text(isRecovery ? .Onboarding.recoveryPrivacy : .Onboarding.suggestionsPrivacy)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let failureMessage {
                    Text(failureMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Text(.Onboarding.changeInSettings)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(.Onboarding.skip) {
                connectionCheck?.cancel()
                onContinue(nil)
            }
            .keyboardShortcut(.cancelAction)
            Button {
                if isEnabled { onContinue(nil) }
                else { checkAgentAndEnable() }
            } label: {
                if connectionCheck != nil {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(Text(.Onboarding.checkingAgent))
                } else {
                    Text(isEnabled ? .Onboarding.continueSetup : isRecovery ? .Onboarding.enableRecovery : .Onboarding.enableSuggestions)
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(connectionCheck != nil)
        }
        .controlSize(.large)
    }

    private var illustration: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(.linearGradient(colors: [tint.opacity(0.23), tint.opacity(0.05)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .strokeBorder(tint.opacity(0.18), lineWidth: 1)
                .frame(width: 215)
            Circle()
                .strokeBorder(tint.opacity(0.12), lineWidth: 1)
                .frame(width: 295)
            HStack(spacing: 22) {
                illustrationTile("internaldrive.fill", foreground: tint, background: .primary.opacity(0.06))
                    .rotationEffect(.degrees(-9))
                Image(systemName: "arrow.right")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(tint)
                illustrationTile(isRecovery ? "bolt.fill" : "checklist", foreground: .white, background: tint)
                    .rotationEffect(.degrees(9))
            }
        }
        .frame(height: 165)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: 24))
        .accessibilityHidden(true)
    }

    private func illustrationTile(_ icon: String, foreground: Color, background: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: 72, height: 72)
            .background(background, in: .rect(cornerRadius: 20))
    }

    private func checkAgentAndEnable() {
        failureMessage = nil
        let agent = selectedAgent
        let configuration = monitor.settings.cleanupConfiguration(for: agent)
        connectionCheck = Task {
            defer { connectionCheck = nil }
            do {
                try await CleanupAgentRunner().checkConnection(configuration)
                try Task.checkCancellation()
                await monitor.notifications.requestPermission()
                try Task.checkCancellation()
                onContinue(agent)
            } catch {
                guard !Task.isCancelled else { return }
                failureMessage = (error as? CleanupScanError ?? .scanFailed).message(for: agent)
            }
        }
    }
}
