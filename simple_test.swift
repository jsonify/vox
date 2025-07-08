#!/usr/bin/env swift

import Foundation
import Speech

// Test with async/await pattern like our code
func testAsync() async throws {
    print("Starting async test...")
    
    // Request permission
    let authStatus = await withCheckedContinuation { continuation in
        SFSpeechRecognizer.requestAuthorization { status in
            continuation.resume(returning: status)
        }
    }
    print("Auth status: \(authStatus)")
    
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot create recognizer"])
    }
    
    print("Recognizer available: \(recognizer.isAvailable)")
    
    let audioURL = URL(fileURLWithPath: "/var/folders/2y/73mzwdf56lqc6z3n6b3bcsqc0000gn/T/vox_audio_017D1F28-34AD-4FAF-B242-01312045D729.m4a")
    let request = SFSpeechURLRecognitionRequest(url: audioURL)
    request.shouldReportPartialResults = true
    request.requiresOnDeviceRecognition = false
    
    let result: String = try await withCheckedThrowingContinuation { continuation in
        var hasResumed = false
        let task = recognizer.recognitionTask(with: request) { result, error in
            if hasResumed { return }
            
            if let error = error {
                hasResumed = true
                continuation.resume(throwing: error)
                return
            }
            
            if let result = result, result.isFinal {
                hasResumed = true
                continuation.resume(returning: result.bestTranscription.formattedString)
            }
        }
        
        // Add timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            if !hasResumed {
                hasResumed = true
                task.cancel()
                continuation.resume(throwing: NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timeout"]))
            }
        }
    }
    
    print("Result: \(result)")
}

// Run the test
Task {
    do {
        try await testAsync()
    } catch {
        print("Error: \(error)")
    }
    exit(0)
}

RunLoop.main.run()