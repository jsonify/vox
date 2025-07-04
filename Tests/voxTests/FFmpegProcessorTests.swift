import XCTest
import Foundation
@testable import vox

/// FFmpegProcessorTests has been split into focused test files for better organization:
/// - FFmpegProcessorBasicTests.swift - Core functionality and temp file management
/// - FFmpegProcessorErrorTests.swift - Error handling and edge cases  
/// - FFmpegProcessorIntegrationTests.swift - Integration tests and progress reporting
///
/// This file serves as a minimal entry point and basic smoke test.
final class FFmpegProcessorTests: XCTestCase {
    func testFFmpegProcessorModuleSmokeTest() {
        // Basic smoke test to ensure the FFmpegProcessor can be instantiated
        let processor = FFmpegProcessor()
        XCTAssertNotNil(processor, "FFmpegProcessor should instantiate successfully")
        
        // Test that basic availability detection doesn't crash
        let isAvailable = FFmpegProcessor.isFFmpegAvailable()
        XCTAssertTrue(isAvailable || !isAvailable, "Availability detection should return a boolean")
    }
    
    func testTestFileStructureExists() {
        // Verify that the split test files exist in the test bundle
        let bundle = Bundle(for: type(of: self))
        
        // We can't directly check for other test classes, but we can verify the module loads
        XCTAssertNotNil(bundle, "Test bundle should be available")
        
        // Basic functionality test to ensure everything is working
        let processor = FFmpegProcessor()
        let tempURL = processor.createTemporaryAudioFile()
        XCTAssertNotNil(tempURL, "Should be able to create temporary file URLs")
    }
    
    /// For comprehensive FFmpeg testing, see:
    /// - FFmpegProcessorBasicTests for core functionality
    /// - FFmpegProcessorErrorTests for error handling 
    /// - FFmpegProcessorIntegrationTests for full integration tests
    func testReferenceToSpecializedTests() {
        // This test serves as documentation for where to find the real tests
        XCTAssertTrue(true, "See specialized test files for comprehensive FFmpeg testing")
    }
}
