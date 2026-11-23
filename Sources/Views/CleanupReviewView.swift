import SwiftUI

struct CleanupReviewView: View {
    let monitor: DiskMonitorService
    @Binding var selectedVolume: URL?

    private var cleanup: CleanupService { monitor.cleanup }

    private var reviewVolumes: [VolumeInfo] {
        let active = Set(cleanup.activeVolumes.map(\.id))
        let recent = monitor.trackedVolumes.filter { cleanup.removalResults[$0.id] != nil && !active.contains($0.id) }
        return cleanup.activeVolumes + recent
    }

    var body: some View {
        VStack(spacing: 0) {
            if reviewVolumes.count > 1 {
                Picker(.Cleanup.volumeLabel, selection: volumeSelection) {
                    ForEach(reviewVolumes) { volume in
                        Text(volume.name).tag(Optional(volume.id))
                    }
                }
                .padding()
                Divider()
            }

            if let volume = reviewVolumes.first(where: { $0.id == volumeSelection.wrappedValue }) {
                CleanupVolumeReview(monitor: monitor, volume: volume)
                    .id(volume.id)
            } else {
                ContentUnavailableView(
                    .Cleanup.reviewEmptyTitle, systemImage: "internaldrive",
                    description: Text(.Cleanup.reviewEmptyDescription)
                )
            }
        }
        .frame(minWidth: 560, minHeight: 400)
    }

    private var volumeSelection: Binding<URL?> {
        Binding(get: {
            if reviewVolumes.contains(where: { $0.id == selectedVolume }) { return selectedVolume }
            return reviewVolumes.first?.id
        }, set: { selectedVolume = $0 })
    }
}

private struct CleanupVolumeReview: View {
    let monitor: DiskMonitorService
    let volume: VolumeInfo

    @State private var selection: Set<UUID> = []
    @State private var pendingApproval: [CleanupProposal] = []
    @State private var confirmingDeletion = false
    @State private var showFailures = false
    @State private var approvalRejected = false

    private var cleanup: CleanupService { monitor.cleanup }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(volume.name)
                    .font(.title2.bold())
                let target = CleanupPolicy.targetBytes(for: volume, thresholds: monitor.settings.alertThresholds)
                Text(.Cleanup.freeSpaceGoal(formatBytes(volume.cleanupFreeBytes), formatBytes(target)))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            if let result = cleanup.removalResults[volume.id] {
                removalSummary(result)
            }

            Divider()
            switch cleanup.statuses[volume.id] {
            case .ready(let plan):
                proposals(plan)
            case .scanning(let attempt):
                statusView {
                    ProgressView(attempt == 1 ? .Cleanup.findingCandidates : .Cleanup.retrying(String(attempt)))
                }
            case .failed(let error, let agent):
                statusView {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(.orange)
                    Text(.Cleanup.scanFailedTitle).font(.headline)
                    Text(error.message(for: agent)).foregroundStyle(.secondary)
                    Button(.Cleanup.retryScan) { cleanup.retry(volume.id) }
                }
            case .noCandidates:
                statusView {
                    Text(.Cleanup.noSuggestionsTitle).font(.headline)
                    Text(.Cleanup.noSuggestionsDescription).foregroundStyle(.secondary)
                    Button(.Cleanup.scanAgain) { cleanup.retry(volume.id) }
                }
            case .deleting:
                statusView { ProgressView(.Cleanup.deleting) }
            case nil:
                statusView {
                    if cleanup.activeVolumes.contains(where: { $0.id == volume.id }) {
                        Text(.Cleanup.waiting).foregroundStyle(.secondary)
                    } else {
                        Text(.Cleanup.cleanupFinished).font(.headline)
                    }
                }
            }
        }
        .alert(.Cleanup.confirmDeletion, isPresented: $confirmingDeletion) {
            Button(.Cleanup.cancel, role: .cancel) { pendingApproval = [] }
            Button(.Cleanup.deletePermanently, role: .destructive) {
                let approved = Set(pendingApproval.map(\.id))
                pendingApproval = []
                selection = []
                Task {
                    if await cleanup.delete(approved, from: volume.id) {
                        monitor.pollVolumes()
                    } else {
                        approvalRejected = true
                    }
                }
            }
        } message: {
            let items = pendingApproval.map {
                String(localized: .Cleanup.confirmationItem($0.title, formatBytes($0.bytes)))
            }
            let notice = String(localized: .Cleanup.confirmationNotice)
            Text(verbatim: ([notice] + items).joined(separator: "\n"))
        }
        .alert(.Cleanup.selectionChanged, isPresented: $approvalRejected) {
            Button(.Cleanup.dismiss, role: .cancel) {}
        } message: {
            Text(.Cleanup.reviewCurrentPlan)
        }
    }

    private func proposals(_ plan: CleanupPlan) -> some View {
        let selected = plan.proposals.filter { selection.contains($0.id) }
        let proposalIDs = Set(plan.proposals.map(\.id))
        let estimatedBytes = selected.reduce(0) { $0 + $1.bytes }
        let availableBytes = plan.proposals.reduce(0) { $0 + $1.bytes }
        let isPartial = (selected.isEmpty ? plan.proposals : selected).contains(where: \.isPartial)
        return VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(plan.proposals) { proposal in
                        CleanupProposalRow(proposal: proposal, selected: selectionBinding(for: proposal.id))
                        Divider()
                    }
                }
                .padding(.horizontal, 20)
            }

            Divider()
            HStack(spacing: 16) {
                Button(.Cleanup.rescan) {
                    selection = []
                    cleanup.retry(volume.id)
                }
                Spacer()
                let amount = formatBytes(selected.isEmpty ? availableBytes : estimatedBytes)
                Text(isPartial ? .Cleanup.partiallyMeasured(amount) : .Cleanup.estimatedSavings(amount))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(.Cleanup.deleteSelected, role: .destructive) {
                    pendingApproval = selected
                    confirmingDeletion = true
                }
                .disabled(selected.isEmpty)
            }
            .padding(16)
        }
        .onChange(of: proposalIDs, initial: true) { _, ids in
            selection.formIntersection(ids)
        }
    }

    private func removalSummary(_ result: CleanupService.RemovalResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(.Cleanup.removedPaths(String(result.removedCount)))
            if !result.failedPaths.isEmpty {
                DisclosureGroup(
                    .Cleanup.failedPaths(String(result.failedPaths.count)), isExpanded: $showFailures
                ) {
                    ScrollView {
                        VStack(alignment: .leading) {
                            ForEach(result.failedPaths, id: \.self) { path in
                                Text(verbatim: path).textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 100)
                }
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func selectionBinding(for id: UUID) -> Binding<Bool> {
        Binding(get: { selection.contains(id) }, set: { selected in
            if selected {
                selection.insert(id)
            } else {
                selection.remove(id)
            }
        })
    }

    private func statusView<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 12, content: content)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CleanupProposalRow: View {
    let proposal: CleanupProposal
    @Binding var selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle(isOn: $selected) {
                HStack {
                    Text(verbatim: proposal.title)
                        .font(.headline)
                    Spacer()
                    let amount = formatBytes(proposal.bytes)
                    Text(proposal.isPartial ? .Cleanup.partialRowSize(amount) : .Cleanup.estimatedRowSize(amount))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            Text(verbatim: proposal.context)
                .foregroundStyle(.secondary)

            DisclosureGroup(.Cleanup.paths(String(proposal.candidates.count))) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(proposal.candidates, id: \.path) { candidate in
                        Text(verbatim: candidate.path)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 5)
            }
            .font(.callout)
        }
        .padding(.vertical, 13)
    }
}
