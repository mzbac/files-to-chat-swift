import Foundation
import CryptoKit
import MLXLMCommon

struct KVCacheStore {
    let modelID: String

    private var cacheDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".cache/files-to-chat-swift/\(modelID)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func fingerprint(for context: String) -> String {
        let data = Data(context.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func cacheURL(for context: String, precision: CachePrecision) -> URL {
        cacheDir.appendingPathComponent("prompt.\(fingerprint(for: context)).\(precision.filenameComponent).safetensors")
    }

    func loadCache(for context: String, precision: CachePrecision) throws -> [KVCache]? {
        let file = cacheURL(for: context, precision: precision)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do {
            let (cache, _) = try loadPromptCache(url: file)
            return cache
        } catch {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
    }

    func persist(cache: [KVCache], context: String, precision: CachePrecision) throws {
        let file = cacheURL(for: context, precision: precision)
        let cachesToPersist: [KVCache] = cache.map { element in
            switch precision {
            case .eightBit:
                if let simple = element as? KVCacheSimple {
                    return simple.toQuantized(groupSize: 64, bits: 8)
                } else if let chunked = element as? ChunkedKVCache {
                    return chunked.toQuantized(groupSize: 64, bits: 8)
                } else if let quantized = element as? QuantizedKVCache {
                    if quantized.bits == 8 { return quantized }
                    let simple = quantized.toUnquantized()
                    return simple.toQuantized(groupSize: quantized.groupSize, bits: 8)
                } else {
                    return element
                }
            case .bf16:
                if let quantized = element as? QuantizedKVCache {
                    return quantized.toUnquantized()
                } else {
                    return element
                }
            }
        }
        try savePromptCache(url: file, cache: cachesToPersist)
    }
}
