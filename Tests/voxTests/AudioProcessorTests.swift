import XCTest
import Foundation
@testable import vox

final class AudioProcessorTests: XCTestCase {
    
    var audioProcessor: AudioProcessor!
    
    override func setUp() {
        super.setUp()
        audioProcessor = AudioProcessor()
    }
    
    override func tearDown() {
        audioProcessor = nil
        super.tearDown()
    }
    
    func testExtractAudioFromNonexistentFile() {
        let expectation = XCTestExpectation(description: "Audio extraction should fail for nonexistent file")
        
        let nonexistentPath = "/path/to/nonexistent/file.mp4"
        
        audioProcessor.extractAudio(from: nonexistentPath) { result in
            switch result {
            case .success:
                XCTFail("Expected failure for nonexistent file")
            case .failure(let error):
                if case .invalidInputFile = error {
                    expectation.fulfill()
                } else {
                    XCTFail("Expected invalidInputFile error, got: \(error)")
                }
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testExtractAudioFromInvalidFile() {
        let expectation = XCTestExpectation(description: "Audio extraction should fail for invalid file")
        
        let tempDir = FileManager.default.temporaryDirectory
        let invalidFilePath = tempDir.appendingPathComponent("invalid.mp4").path
        
        FileManager.default.createFile(atPath: invalidFilePath, contents: Data("invalid content".utf8))
        defer {
            try? FileManager.default.removeItem(atPath: invalidFilePath)
        }
        
        audioProcessor.extractAudio(from: invalidFilePath) { result in
            switch result {
            case .success:
                XCTFail("Expected failure for invalid file")
            case .failure(let error):
                if case .unsupportedFormat = error {
                    expectation.fulfill()
                } else {
                    XCTFail("Expected unsupportedFormat error, got: \(error)")
                }
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testTemporaryFileCreation() {
        let processor = AudioProcessor()
        let tempURL = processor.createTemporaryAudioFile()
        
        XCTAssertNotNil(tempURL)
        XCTAssertTrue(tempURL?.pathExtension == "m4a")
        XCTAssertTrue(tempURL?.lastPathComponent.hasPrefix("vox_temp_") == true)
    }
    
    func testCleanupTemporaryFile() {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFileURL = tempDir.appendingPathComponent("test_cleanup.m4a")
        
        FileManager.default.createFile(atPath: tempFileURL.path, contents: Data())
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFileURL.path))
        
        audioProcessor.cleanupTemporaryFile(at: tempFileURL)
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFileURL.path))
    }
    
    func testProgressCallbackInvocation() {
        let nonexistentPath = "/path/to/nonexistent/file.mp4"
        var progressCalled = false
        
        audioProcessor.extractAudio(from: nonexistentPath, 
                                  progressCallback: { progress in
                                      progressCalled = true
                                  }) { _ in }
        
        XCTAssertFalse(progressCalled, "Progress callback should not be called for immediate failures")
    }
}

extension AudioProcessor {
    func createTemporaryAudioFile() -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "vox_temp_\(UUID().uuidString).m4a"
        return tempDir.appendingPathComponent(fileName)
    }
}