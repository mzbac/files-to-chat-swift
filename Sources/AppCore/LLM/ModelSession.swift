import Foundation
import MLXLLM
import MLXLMCommon

public enum CachePrecision: String, Sendable {
    case eightBit
    case bf16

    public var filenameComponent: String {
        switch self {
        case .eightBit: return "8bit"
        case .bf16: return "bf16"
        }
    }
}

public final class ModelSession {
    private let session: PersistentChatSession
    private let cacheStore: KVCacheStore
    private let cachePrecision: CachePrecision

    private init(session: PersistentChatSession, cacheStore: KVCacheStore, cachePrecision: CachePrecision) {
        self.session = session
        self.cacheStore = cacheStore
        self.cachePrecision = cachePrecision
    }

    public static func load(modelID: String, cachePrecision: CachePrecision) async throws -> ModelSession {
        let model = try await loadModelContainer(id: modelID)
        let chatSession = PersistentChatSession(model: model)
        return ModelSession(session: chatSession, cacheStore: KVCacheStore(modelID: modelID), cachePrecision: cachePrecision)
    }

    public struct PrefillResult: Sendable {
        public let usedCache: Bool
        public let cachePath: String
        public let elapsed: TimeInterval
    }

    public func prefillAndPersist(context: String) async throws -> PrefillResult {
        let start = Date()
        let cacheURL = cacheStore.cacheURL(for: context, precision: cachePrecision)
        if let caches = try cacheStore.loadCache(for: context, precision: cachePrecision) {
            await session.loadCache(caches)
            return PrefillResult(usedCache: true, cachePath: cacheURL.path, elapsed: Date().timeIntervalSince(start))
        }
        try await session.warm(with: context)
        try await session.persistCache(using: cacheStore, context: context, precision: cachePrecision)
        return PrefillResult(usedCache: false, cachePath: cacheURL.path, elapsed: Date().timeIntervalSince(start))
    }

    public func streamAnswer(question: String) -> AsyncThrowingStream<String, Error> {
        session.streamAnswer(question: question)
    }
}

extension ModelSession: @unchecked Sendable {}
