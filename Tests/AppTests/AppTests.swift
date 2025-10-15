import XCTest
import AppCore
import PDFKit
import AppKit

final class AppTests: XCTestCase {
    func testCollectTextFiles() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        let a = tmp.appendingPathComponent("a.txt"); try "hello".write(to: a, atomically: true, encoding: .utf8)
        let b = tmp.appendingPathComponent("b.md"); try "nope".write(to: b, atomically: true, encoding: .utf8)

        let files = try TextLoader.collectTextFiles(at: tmp)
        XCTAssertEqual(files.map { $0.lastPathComponent }, ["a.txt"])
    }

    func testCollectTextFilesRecursesIntoSubdirectories() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        let nested = tmp.appendingPathComponent("nested")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)

        let root = tmp.appendingPathComponent("root.txt")
        let child = nested.appendingPathComponent("child.TXT")
        try "root".write(to: root, atomically: true, encoding: .utf8)
        try "child".write(to: child, atomically: true, encoding: .utf8)

        let files = try TextLoader.collectTextFiles(at: tmp)
        XCTAssertEqual(files.map { $0.lastPathComponent }.sorted(), ["child.TXT", "root.txt"])
    }

    func testCollectTextFilesAggregatesMultipleInputs() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        let nested = tmp.appendingPathComponent("nested")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)

        let direct = tmp.appendingPathComponent("direct.txt")
        let nestedFile = nested.appendingPathComponent("nested.txt")
        try "direct".write(to: direct, atomically: true, encoding: .utf8)
        try "nested".write(to: nestedFile, atomically: true, encoding: .utf8)

        let files = try TextLoader.collectTextFiles(paths: [direct.path, nested.path, tmp.path])
        XCTAssertEqual(files.map { $0.lastPathComponent }, ["direct.txt", "nested.txt"])
    }

    func testCollectTextFilesRespectsCustomExtensions() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)

        let md = tmp.appendingPathComponent("doc.md")
        let txt = tmp.appendingPathComponent("note.txt")
        try "markdown".write(to: md, atomically: true, encoding: .utf8)
        try "text".write(to: txt, atomically: true, encoding: .utf8)

        let mdOnly = try TextLoader.collectTextFiles(paths: [tmp.path], allowedExtensions: ["md"])
        XCTAssertEqual(mdOnly.map { $0.lastPathComponent }, ["doc.md"])

        let both = try TextLoader.collectTextFiles(paths: [tmp.path], allowedExtensions: ["md", "txt"])
        XCTAssertEqual(both.map { $0.lastPathComponent }.sorted(), ["doc.md", "note.txt"])
    }

    func testCollectTextFilesAppliesExclusions() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)

        let md = tmp.appendingPathComponent("doc.md")
        let swift = tmp.appendingPathComponent("code.swift")
        try "markdown".write(to: md, atomically: true, encoding: .utf8)
        try "swift".write(to: swift, atomically: true, encoding: .utf8)

        let allButMarkdown = try TextLoader.collectTextFiles(
            paths: [tmp.path],
            allowedExtensions: nil,
            excludedExtensions: ["md"]
        )
        XCTAssertEqual(allButMarkdown.map { $0.lastPathComponent }, ["code.swift"])
    }

    func testPromptBuilder() {
        let doc = "some text"
        let ctx = PromptBuilder.makeContext(documentsText: doc)
        XCTAssertTrue(ctx.contains("### DOCUMENTS"))
        XCTAssertTrue(ctx.contains(doc))
    }

    func testOCRExtractionFromPDF() async throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        let pdfURL = tmp.appendingPathComponent("ocr.pdf")

        try createPdf(with: "Hello OCR", at: pdfURL)
        let combined = try await TextLoader.readAndConcatenate(files: [pdfURL])
        XCTAssertTrue(combined.contains("Hello OCR"))
    }
}

private func createPdf(with text: String, at url: URL) throws {
    let size = NSSize(width: 400, height: 200)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.white.setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 48, weight: .bold),
        .foregroundColor: NSColor.black
    ]
    let textRect = NSRect(x: 20, y: (size.height - 60) / 2, width: size.width - 40, height: 60)
    (text as NSString).draw(in: textRect, withAttributes: attributes)
    image.unlockFocus()

    guard let page = PDFPage(image: image) else {
        throw NSError(domain: "AppTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create PDF page"])
    }

    let document = PDFDocument()
    document.insert(page, at: 0)
    if !document.write(to: url) {
        throw NSError(domain: "AppTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to write PDF"])
    }
}
