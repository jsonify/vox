#!/usr/bin/env swift

import Foundation
import Speech
import AVFoundation

@available(macOS 10.15, *)
class SimpleSpeechTranscriber {
    private let speechRecognizer: SFSpeechRecognizer
    private var recognitionTask: SFSpeechRecognitionTask?
    
    init() throws {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot create recognizer"])
        }
        
        guard recognizer.isAvailable else {
            throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Recognizer not available"])
        }
        
        self.speechRecognizer = recognizer
        
        // Request permission
        let semaphore = DispatchSemaphore(value: 0)
        var authError: Error?
        
        SFSpeechRecognizer.requestAuthorization { status in
            switch status {
            case .authorized:
                break
            default:
                authError = NSError(domain: "Test", code: 3, userInfo: [NSLocalizedDescriptionKey: "Not authorized"])
            }
            semaphore.signal()
        }
        semaphore.wait()
        
        if let error = authError {
            throw error
        }
    }
    
    func transcribe(audioPath: String) async throws -> String {
        let audioURL = URL(fileURLWithPath: audioPath)
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        
        let result: SFSpeechRecognitionResult = try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            
            recognitionTask = speechRecognizer.recognitionTask(with: request) { result, error in
                if hasResumed { return }
                
                if let error = error {
                    hasResumed = true
                    continuation.resume(throwing: error)
                    return
                }
                
                if let result = result, result.isFinal {
                    hasResumed = true
                    continuation.resume(returning: result)
                } else if let result = result {
                    print("Partial: \(result.bestTranscription.formattedString)")
                }
            }
            
            // Timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
                if !hasResumed {
                    hasResumed = true
                    self?.recognitionTask?.cancel()
                    continuation.resume(throwing: NSError(domain: "Test", code: 4, userInfo: [NSLocalizedDescriptionKey: "Timeout"]))
                }
            }
        }
        
        return result.bestTranscription.formattedString
    }
}

func testDirectly() async {
    do {
        let transcriber = try SimpleSpeechTranscriber()
        let result = try await transcriber.transcribe(audioPath: "/var/folders/2y/73mzwdf56lqc6z3n6b3bcsqc0000gn/T/vox_audio_017D1F28-34AD-4FAF-B242-01312045D729.m4a")
        print("Result: \(result)")
    } catch {
        print("Error: \(error)")
    }
}

Task {
    await testDirectly()
    exit(0)
}

RunLoop.main.run()