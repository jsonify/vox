#!/usr/bin/env swift

import Foundation

// Test if TempFileManager.shared causes static initialization crash
class MinimalTempFileManager {
    static let shared = MinimalTempFileManager()
    
    private init() {
        print("MinimalTempFileManager init started")
        setupCleanupOnExit()
        print("MinimalTempFileManager init completed")
    }
    
    private func setupCleanupOnExit() {
        print("Setting up cleanup handlers...")
        
        // This is likely the culprit - atexit registration during static init
        atexit {
            print("atexit cleanup called")
        }
        
        // Signal handlers during static init
        signal(SIGINT) { _ in
            print("SIGINT cleanup called")
        }
        
        print("Cleanup handlers registered")
    }
}

print("About to access MinimalTempFileManager.shared")
let manager = MinimalTempFileManager.shared
print("Successfully accessed MinimalTempFileManager.shared")
print("Test completed successfully")