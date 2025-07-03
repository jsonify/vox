#!/usr/bin/env swift

import Foundation

// Test the actual initialization path that causes the crash
print("Testing AudioProcessor initialization path...")

// First test Logger.shared (already known to work with fix)
print("1. Testing Logger.shared access...")
class MockLogger {
    static let shared = MockLogger()
    private init() {
        print("  MockLogger initialized")
    }
}
let logger = MockLogger.shared
print("✓ MockLogger.shared works")

// Test TempFileManager.shared initialization path
print("2. Testing TempFileManager-like initialization...")
class MockTempFileManager {
    static let shared = MockTempFileManager()
    private init() {
        print("  MockTempFileManager init started")
        setupCleanupOnExit()
        print("  MockTempFileManager init completed")
    }
    
    private func setupCleanupOnExit() {
        print("    Setting up cleanup handlers...")
        
        // This could be the issue - recursive shared access in atexit
        atexit {
            print("atexit: accessing shared instance")
            MockTempFileManager.shared.cleanupAllFiles()
        }
        
        signal(SIGINT) { _ in
            print("SIGINT: accessing shared instance")
            MockTempFileManager.shared.cleanupAllFiles()
            exit(SIGINT)
        }
        
        signal(SIGTERM) { _ in  
            print("SIGTERM: accessing shared instance")
            MockTempFileManager.shared.cleanupAllFiles()
            exit(SIGTERM)
        }
        
        print("    Cleanup handlers registered")
    }
    
    func cleanupAllFiles() {
        print("    cleanupAllFiles called")
    }
}

print("About to access MockTempFileManager.shared...")
let tempManager = MockTempFileManager.shared
print("✓ MockTempFileManager.shared works")

// Test AudioProcessor-like initialization
print("3. Testing AudioProcessor-like initialization...")
class MockAudioProcessor {
    private let logger = MockLogger.shared
    private let tempFileManager = MockTempFileManager.shared
    
    init() {
        print("  MockAudioProcessor initialized")
    }
}

print("About to create MockAudioProcessor...")
let audioProcessor = MockAudioProcessor()
print("✓ MockAudioProcessor works")

print("All tests passed - the crash might be elsewhere")