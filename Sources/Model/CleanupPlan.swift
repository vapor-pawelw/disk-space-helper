import Foundation

struct CleanupCandidate: Sendable {
    enum Kind: String, Encodable, Sendable {
        case trash, installer, archive, xcodeArchive, oldDownload, buildOutput, dependencyCache, cache

        var priority: Int {
            switch self {
            case .trash, .installer: 0
            case .archive, .oldDownload, .buildOutput: 1
            case .xcodeArchive, .dependencyCache, .cache: 2
            }
        }
    }

    let path: String
    let bytes: Int64
    let kind: Kind
    let identity: CleanupFileIdentity
    var isPartial = false
}

struct CleanupProposal: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let context: String
    let candidates: [CleanupCandidate]

    var bytes: Int64 { candidates.reduce(0) { $0 + $1.bytes } }
    var isPartial: Bool { candidates.contains(where: \.isPartial) }
}

struct CleanupPlan: Sendable {
    let proposals: [CleanupProposal]

    func approvedCandidates(for ids: Set<UUID>) -> [CleanupCandidate]? {
        let selected = proposals.filter { ids.contains($0.id) }
        guard !ids.isEmpty, selected.count == ids.count else { return nil }
        return selected.flatMap(\.candidates)
    }

    static func decode(_ data: Data, inventory: [CleanupCandidate]) throws -> Self {
        let ranking = try JSONDecoder().decode(Ranking.self, from: data)
        let minimum = min(5, inventory.count)
        guard (minimum...min(10, inventory.count)).contains(ranking.proposals.count) else {
            throw CleanupScanError.invalidResponse
        }

        var used: Set<Int> = []
        let proposals = try ranking.proposals.map { proposal in
            let title = proposal.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let context = proposal.context.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (1...70).contains(title.count), (1...200).contains(context.count),
                  !title.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  !context.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  !proposal.candidateIDs.isEmpty else {
                throw CleanupScanError.invalidResponse
            }

            let candidates = try proposal.candidateIDs.map { id in
                guard inventory.indices.contains(id), used.insert(id).inserted else {
                    throw CleanupScanError.invalidResponse
                }
                return inventory[id]
            }
            return CleanupProposal(title: title, context: context, candidates: candidates)
        }

        return Self(proposals: proposals)
    }

    private struct Ranking: Decodable {
        struct Proposal: Decodable {
            let title: String
            let context: String
            let candidateIDs: [Int]
        }

        let proposals: [Proposal]
    }
}
