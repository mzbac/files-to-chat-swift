import Foundation
import MLX
import MLXLLM
@preconcurrency import MLXLMCommon

actor PersistentChatSession {
    private final class CacheBox: @unchecked Sendable {
        var value: [KVCache]
        init(value: [KVCache]) { self.value = value }
    }

    private enum Message: Sendable {
        case system(String)
        case user(String)
        case assistant(String)

        func toChatMessage() -> Chat.Message {
            switch self {
            case .system(let text): return .system(text)
            case .user(let text): return .user(text)
            case .assistant(let text): return .assistant(text)
            }
        }
    }

    private let model: ModelContainer
    private let processing: UserInput.Processing
    private let parameters: GenerateParameters
    private var history: [Message]
    private var cache: [KVCache]

    init(
        model: ModelContainer,
        instructions: String? = nil,
        parameters: GenerateParameters = .init(),
        processing: UserInput.Processing = .init(resize: CGSize(width: 512, height: 512))
    ) {
        self.model = model
        self.processing = processing
        self.parameters = parameters
        var messages: [Message] = []
        if let instructions {
            messages.append(.system(instructions))
        }
        self.history = messages
        self.cache = []
    }

    func loadCache(_ caches: [KVCache]) {
        cache = caches
    }

    func persistCache(using store: KVCacheStore, context: String, precision: CachePrecision) throws {
        try store.persist(cache: cache, context: context, precision: precision)
    }

    func warm(with prompt: String) async throws {
        try await generate(prompt: prompt, recordHistory: false, onChunk: nil)
    }

    nonisolated func streamAnswer(question: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { await self.stream(prompt: question, recordHistory: true, continuation: continuation) }
        }
    }

    private func stream(
        prompt: String,
        recordHistory: Bool,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        do {
            try await generate(prompt: prompt, recordHistory: recordHistory) { chunk in
                continuation.yield(chunk)
            }
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private func generate(
        prompt: String,
        recordHistory: Bool,
        onChunk: (@Sendable (String) -> Void)?
    ) async throws {
        let historySnapshot = history
        let cacheBox = CacheBox(value: cache)
        let aggregated = try await model.perform { context -> String in
            let chatMessages = historySnapshot.map { $0.toChatMessage() } + [.user(prompt)]
            let userInput = UserInput(chat: chatMessages, processing: processing)
            let input = try await context.processor.prepare(input: userInput)

            var caches = cacheBox.value
            if caches.isEmpty {
                caches = context.model.newCache(parameters: parameters)
            }

            let generationStream = try MLXLMCommon.generate(
                input: input,
                cache: caches,
                parameters: parameters,
                context: context
            )

            var collected = ""
            for await generation in generationStream {
                if let chunk = generation.chunk {
                    collected.append(chunk)
                    onChunk?(chunk)
                }
            }

            Stream.gpu.synchronize()
            cacheBox.value = caches
            return collected
        }

        cache = cacheBox.value

        if recordHistory {
            history.append(.user(prompt))
            if !aggregated.isEmpty {
                history.append(.assistant(aggregated))
            }
        }
    }
}

extension PersistentChatSession: @unchecked Sendable {}
