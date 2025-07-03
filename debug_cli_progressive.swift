#!/usr/bin/env swift

import Foundation

// Progressive debug test to find exact crash point in CLI path
print("=== Progressive CLI Debug Test ===")

print("Step 1: Basic Swift execution")
print("✓ Basic Swift works")

print("Step 2: Foundation imports")
import ArgumentParser
print("✓ ArgumentParser import works")

print("Step 3: Define simple ParsableCommand")
struct DebugVox: ParsableCommand {
    @Argument(help: "Input file")
    var inputFile: String
    
    func run() throws {
        print("DEBUG: Entered run() method")
        print("DEBUG: inputFile = \(inputFile)")
        
        print("DEBUG: About to test Logger creation...")
        testLoggerCreation()
        
        print("DEBUG: About to test TempFileManager...")
        testTempFileManager()
        
        print("DEBUG: About to test AudioProcessor...")
        testAudioProcessorCreation()
        
        print("DEBUG: All tests passed in run()")
    }
}

print("Step 4: Define test functions")

func testLoggerCreation() {
    print("  Creating Logger...")
    // Simulate Logger.shared access
    class TestLogger {
        static let shared = TestLogger()
        private init() {
            print("    TestLogger initialized")
        }
    }
    let _ = TestLogger.shared
    print("  ✓ Logger test passed")
}

func testTempFileManager() {
    print("  Creating TempFileManager...")
    class TestTempFileManager {
        static let shared = TestTempFileManager()
        private init() {
            print("    TestTempFileManager init")
            // Simplified setup - no atexit for now
            print("    TestTempFileManager setup complete")
        }
    }
    let _ = TestTempFileManager.shared
    print("  ✓ TempFileManager test passed")
}

func testAudioProcessorCreation() {
    print("  Creating AudioProcessor...")
    class TestAudioProcessor {
        init() {
            print("    TestAudioProcessor initialized")
        }
    }
    let _ = TestAudioProcessor()
    print("  ✓ AudioProcessor test passed")
}

print("Step 5: About to call DebugVox.main()")
DebugVox.main()