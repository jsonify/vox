#!/usr/bin/env swift

import Foundation
import Speech

// Simple test to verify Speech framework works
print("Testing Speech framework...")

// Request permission
let semaphore = DispatchSemaphore(value: 0)
SFSpeechRecognizer.requestAuthorization { status in
    print("Authorization status: \(status)")
    semaphore.signal()
}
semaphore.wait()

// Test basic recognizer
guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
    print("ERROR: Cannot create speech recognizer")
    exit(1)
}

print("Recognizer available: \(recognizer.isAvailable)")
print("Supported locales: \(SFSpeechRecognizer.supportedLocales().count)")

// Test with a simple audio file
let audioURL = URL(fileURLWithPath: "/var/folders/2y/73mzwdf56lqc6z3n6b3bcsqc0000gn/T/vox_audio_017D1F28-34AD-4FAF-B242-01312045D729.m4a")
if FileManager.default.fileExists(atPath: audioURL.path) {
    print("Audio file exists")
    let request = SFSpeechURLRecognitionRequest(url: audioURL)
    request.shouldReportPartialResults = false
    request.requiresOnDeviceRecognition = false
    
    let task = recognizer.recognitionTask(with: request) { result, error in
        if let error = error {
            print("Recognition error: \(error)")
            exit(1)
        }
        
        if let result = result {
            print("Recognition result: \(result.bestTranscription.formattedString)")
            if result.isFinal {
                print("Final result received")
                exit(0)
            }
        }
    }
    
    // Give it time to process
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 30))
    print("Timeout reached")
    task.cancel()
} else {
    print("Audio file doesn't exist")
}