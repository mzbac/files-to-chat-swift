import Foundation
import AppCore

@main
struct AppMain {
    private static let defaultModelID = "mlx-community/Qwen3-4B-Instruct-2507-4bit-DWQ-2510"
    private static let helpFlags: Set<String> = ["-h", "--help"]
    private static let extensionFlags: Set<String> = ["-e", "--ext"]
    private static let excludeFlags: Set<String> = ["-x", "--exclude"]
    private static let precisionFlags: Set<String> = ["--cache-precision"]
    private static let defaultExtensions: Set<String> = ["txt"]
    private static let usage = """
    files-to-chat-swift

    Usage:
      files-to-chat-swift [options] <file-or-dir> [more-paths...]

    Options:
      -h, --help           Show this help text and exit.
      -e, --ext EXT        Include files matching extension EXT (repeatable, accepts comma-separated lists). Defaults to .txt.
      -x, --exclude EXT    Exclude files matching extension EXT (repeatable, accepts comma-separated lists).
      --cache-precision P  Choose prompt cache precision: 8bit (default) or bf16.

    Environment:
      MODEL_ID      Override the model identifier (default: \(Self.defaultModelID))

    Cache:
      Remove cached prompts by deleting files under
      ~/.cache/files-to-chat-swift/<MODEL_ID>/prompt.*.prefix.txt
    """

    private static func printUsage(to stream: UnsafeMutablePointer<FILE>) {
        fputs(Self.usage + "\n", stream)
    }

    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains(where: helpFlags.contains) {
            printUsage(to: stdout)
            exit(0)
        }

        let parsed = parseInputs(args: args)
        guard let parsed else {
            exit(64)
        }
        let (allowedExtensions, excludedExtensions, cachePrecision, paths) = parsed
        let modelID = ProcessInfo.processInfo.environment["MODEL_ID"]
            ?? Self.defaultModelID

        do {
            let urls = try TextLoader.collectTextFiles(
                paths: paths,
                allowedExtensions: allowedExtensions,
                excludedExtensions: excludedExtensions
            )
            guard !urls.isEmpty else {
                let includeDescription: String
                if let allowedExtensions {
                    let list = allowedExtensions.sorted().map { ".\($0)" }.joined(separator: ", ")
                    includeDescription = list
                } else {
                    includeDescription = "requested"
                }
                let excludeDescription = excludedExtensions.isEmpty
                    ? ""
                    : " (excluding \(excludedExtensions.sorted().map { ".\($0)" }.joined(separator: ", ")))"
                print("No files matching \(includeDescription)\(excludeDescription) found in provided input.")
                return
            }
            print("Preparing documents…")
            let combined = try await TextLoader.readAndConcatenate(files: urls)
            print("Text preparation complete. Building model context…")
            let context = PromptBuilder.makeContext(documentsText: combined)
            print("Loading model \(modelID)…")
            let modelStart = Date()
            let session = try await ModelSession.load(modelID: modelID, cachePrecision: cachePrecision)
            let modelDuration = Date().timeIntervalSince(modelStart)
            print(String(format: "Model loaded in %.2f seconds.", modelDuration))
            print("Priming model session (cache precision: \(cachePrecision.filenameComponent))…")
            let prefill = try await session.prefillAndPersist(context: context)
            let reuseNote = prefill.usedCache ? "Reused cached prompt" : "Cached new prompt"
            print(String(format: "%@ in %.2f seconds at %@", reuseNote, prefill.elapsed, prefill.cachePath))
            print("Context ready. Ask questions about the documents. Type 'exit' to quit.")
            while true {
                fputs("> ", stdout)
                guard let line = readLine(strippingNewline: true), !line.isEmpty else { continue }
                if line == "exit" { break }
                var emitted = false
                do {
                    for try await chunk in session.streamAnswer(question: line) {
                        emitted = true
                        fputs(chunk, stdout)
                        fflush(stdout)
                    }
                    if emitted { fputs("\n", stdout); fflush(stdout) }
                } catch {
                    fputs("\n[Error streaming response: \(error)]\n", stderr)
                }
            }
        } catch {
            fputs("Error: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func parseInputs(
        args: [String]
    ) -> (allowedExtensions: Set<String>?, excludedExtensions: Set<String>, precision: CachePrecision, paths: [String])? {
        if args.isEmpty {
            printUsage(to: stderr)
            return nil
        }
        var allowedExtensions: Set<String>? = defaultExtensions
        var usingDefaultExtensions = true
        var excludedExtensions = Set<String>()
        var cachePrecision: CachePrecision = .eightBit
        var paths: [String] = []
        var index = 0

        func applyExtensionList(_ raw: String) -> Bool {
            let candidates = raw.split(separator: ",").map { String($0) }
            guard !candidates.isEmpty else {
                fputs("Missing extension value.\n", stderr)
                return false
            }
            for candidate in candidates {
                guard let normalized = normalizeExtension(candidate) else {
                    fputs("Invalid extension value '\(candidate)'.\n", stderr)
                    return false
                }
                if normalized == "*" || normalized == "all" {
                    allowedExtensions = nil
                    usingDefaultExtensions = false
                    continue
                }
                if usingDefaultExtensions {
                    allowedExtensions = []
                    usingDefaultExtensions = false
                }
                if allowedExtensions == nil {
                    allowedExtensions = []
                }
                allowedExtensions?.insert(normalized)
            }
            return true
        }

        func applyExcludeList(_ raw: String) -> Bool {
            let candidates = raw.split(separator: ",").map { String($0) }
            guard !candidates.isEmpty else {
                fputs("Missing exclusion value.\n", stderr)
                return false
            }
            for candidate in candidates {
                guard let normalized = normalizeExtension(candidate) else {
                    fputs("Invalid exclusion value '\(candidate)'.\n", stderr)
                    return false
                }
                excludedExtensions.insert(normalized)
            }
            return true
        }

        func applyPrecision(_ raw: String) -> Bool {
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch normalized {
            case "", "8", "8bit", "int8":
                cachePrecision = .eightBit
            case "bf16", "bfloat16", "16":
                cachePrecision = .bf16
            default:
                fputs("Invalid cache precision '\(raw)'. Use 8bit or bf16.\n", stderr)
                return false
            }
            return true
        }

        while index < args.count {
            let arg = args[index]
            if extensionFlags.contains(arg) {
                let nextIndex = index + 1
                guard nextIndex < args.count else {
                    fputs("Missing value after \(arg).\n", stderr)
                    return nil
                }
                let value = args[nextIndex]
                guard applyExtensionList(value) else { return nil }
                index += 2
                continue
            } else if excludeFlags.contains(arg) {
                let nextIndex = index + 1
                guard nextIndex < args.count else {
                    fputs("Missing value after \(arg).\n", stderr)
                    return nil
                }
                let value = args[nextIndex]
                guard applyExcludeList(value) else { return nil }
                index += 2
                continue
            } else if let value = arg.dropFirstExtensionValue(prefixes: ["--ext=", "-e="]) {
                guard applyExtensionList(value) else { return nil }
                index += 1
                continue
            } else if let value = arg.dropFirstExtensionValue(prefixes: ["--exclude=", "-x="]) {
                guard applyExcludeList(value) else { return nil }
                index += 1
                continue
            } else if precisionFlags.contains(arg) {
                let nextIndex = index + 1
                guard nextIndex < args.count else {
                    fputs("Missing value after \(arg).\n", stderr)
                    return nil
                }
                guard applyPrecision(args[nextIndex]) else { return nil }
                index += 2
                continue
            } else if let value = arg.dropFirstExtensionValue(prefixes: ["--cache-precision="]) {
                guard applyPrecision(value) else { return nil }
                index += 1
                continue
            } else if helpFlags.contains(arg) {
                index += 1
                continue
            } else if arg.hasPrefix("-") {
                fputs("Unknown option '\(arg)'.\n", stderr)
                return nil
            } else {
                paths.append(arg)
                index += 1
            }
        }

        if paths.isEmpty {
            fputs("No input paths provided.\n", stderr)
            return nil
        }
        if var allowed = allowedExtensions {
            allowed.subtract(excludedExtensions)
            if allowed.isEmpty {
                fputs("No extensions remain after applying exclusions.\n", stderr)
                return nil
            }
            allowedExtensions = allowed
        }
        return (allowedExtensions, excludedExtensions, cachePrecision, paths)
    }

    private static func normalizeExtension(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withoutDot = trimmed.hasPrefix(".") ? String(trimmed.dropFirst()) : trimmed
        let lowered = withoutDot.lowercased()
        return lowered.isEmpty ? nil : lowered
    }
}

private extension String {
    func dropFirstExtensionValue(prefixes: [String]) -> String? {
        for prefix in prefixes {
            if hasPrefix(prefix) {
                let remainder = dropFirst(prefix.count)
                return String(remainder)
            }
        }
        return nil
    }
}
