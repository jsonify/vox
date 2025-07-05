import XCTest
@testable import vox

class OutputWriterTests: XCTestCase {
    var outputWriter: OutputWriter!
    var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        
        // Create temporary directory for tests
        let tempPath = "vox-output-tests-\(UUID().uuidString)"
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(tempPath)
        do {
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        } catch {
            XCTFail("Failed to create temp directory: \(error)")
        }
        
        outputWriter = OutputWriter()
    }
    
    override func tearDown() {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }
    
    // MARK: - Basic Writing Tests
    
    func testBasicContentWriting() throws {
        let outputPath = tempDirectory.appendingPathComponent("test.txt").path
        let testContent = "Hello world, this is a test."
        
        try outputWriter.writeContentSafely(testContent, to: outputPath)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
        let content = try String(contentsOfFile: outputPath)
        XCTAssertEqual(content, testContent)
    }
    
    // MARK: - Path Validation Tests
    
    func testInvalidPathValidation() {
        let invalidPath = ""
        let testContent = "test content"
        
        XCTAssertThrowsError(try outputWriter.writeContentSafely(testContent, to: invalidPath)) { error in
            guard case VoxError.invalidOutputPath = error else {
                XCTFail("Expected invalidOutputPath error")
                return
            }
        }
    }
    
    func testDirectoryCreation() throws {
        let newDir = tempDirectory.appendingPathComponent("newdir/subdir")
        let outputPath = newDir.appendingPathComponent("test.txt").path
        let testContent = "test content"
        
        // Should create directories automatically
        try outputWriter.writeContentSafely(testContent, to: outputPath)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
        let content = try String(contentsOfFile: outputPath)
        XCTAssertEqual(content, testContent)
    }
    
    // MARK: - Atomic Writing Tests
    
    func testAtomicWriting() throws {
        let outputPath = tempDirectory.appendingPathComponent("atomic.txt").path
        let testContent = "Atomic write test content"
        
        // Write should be atomic - either completely succeeds or fails
        try outputWriter.writeContentSafely(testContent, to: outputPath)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
        let content = try String(contentsOfFile: outputPath)
        XCTAssertEqual(content, testContent)
        
        // No temporary files should remain
        let tempFiles = try FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains(".tmp.") }
        XCTAssertTrue(tempFiles.isEmpty, "Temporary files should be cleaned up")
    }
}
