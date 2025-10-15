import Foundation

public enum TextLoader {
    public static func collectTextFiles(
        at url: URL,
        allowedExtensions: Set<String>? = ["txt"],
        excludedExtensions: Set<String> = []
    ) throws -> [URL] {
        let fm = FileManager.default
        let standardized = url.standardizedFileURL
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: standardized.path, isDirectory: &isDir) else { return [] }
        if isDir.boolValue {
            guard let enumerator = fm.enumerator(
                at: standardized,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }

            var collected: [URL] = []
            for case let fileURL as URL in enumerator {
                let standardizedFile = fileURL.standardizedFileURL
                let ext = standardizedFile.pathExtension.lowercased()
                if let allowedExtensions, !allowedExtensions.contains(ext) { continue }
                if excludedExtensions.contains(ext) { continue }
                let resourceValues = try standardizedFile.resourceValues(forKeys: [.isDirectoryKey])
                if resourceValues.isDirectory == true { continue }
                collected.append(standardizedFile)
            }
            collected.sort { $0.path < $1.path }
            return collected
        } else {
            let ext = standardized.pathExtension.lowercased()
            if let allowedExtensions, !allowedExtensions.contains(ext) { return [] }
            if excludedExtensions.contains(ext) { return [] }
            return [standardized]
        }
    }

    public static func collectTextFiles(
        paths: [String],
        allowedExtensions: Set<String>? = ["txt"],
        excludedExtensions: Set<String> = []
    ) throws -> [URL] {
        var seen = Set<URL>()
        var aggregated: [URL] = []
        for path in paths {
            let baseURL = URL(fileURLWithPath: path)
            let files = try collectTextFiles(
                at: baseURL,
                allowedExtensions: allowedExtensions,
                excludedExtensions: excludedExtensions
            )
            for file in files {
                if seen.insert(file).inserted {
                    aggregated.append(file)
                }
            }
        }
        return aggregated
    }

    public static func readAndConcatenate(files: [URL]) async throws -> String {
        var sections: [String] = []
        for url in files {
            let body: String
            let ext = url.pathExtension.lowercased()
            if ext == "pdf" {
                body = try PDFTextExtractor.extractText(from: url)
            } else {
                body = try String(contentsOf: url, encoding: .utf8)
            }
            sections.append("[File: \(url.lastPathComponent)]\n\(body)\n")
        }
        return sections.joined(separator: "\n")
    }
}
