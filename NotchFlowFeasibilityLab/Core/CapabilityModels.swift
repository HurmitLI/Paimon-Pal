import Foundation

enum CapabilityState: String, Codable, CaseIterable {
    case notRun = "未测试"
    case passed = "通过"
    case passedWithLimitations = "有限通过"
    case failed = "失败"
    case unavailable = "当前环境不可测"
}

struct CapabilityResult: Identifiable, Codable, Equatable {
    let id: UUID
    let capability: String
    let state: CapabilityState
    let summary: String
    let evidence: [String]
    let testedAt: Date

    init(
        id: UUID = UUID(),
        capability: String,
        state: CapabilityState,
        summary: String,
        evidence: [String] = [],
        testedAt: Date = Date()
    ) {
        self.id = id
        self.capability = capability
        self.state = state
        self.summary = summary
        self.evidence = evidence
        self.testedAt = testedAt
    }
}

