#!/usr/bin/swift

import Foundation

func countLines(in filePath: String) -> Int {
    guard let contents = try? String(contentsOfFile: filePath, encoding: .utf8) else {
        return 0
    }
    return contents.components(separatedBy: .newlines).count
}

func findLargeFiles(in directory: String, threshold: Int) -> [(String, Int)] {
    let fileManager = FileManager.default
    var results: [(String, Int)] = []
    
    guard let enumerator = fileManager.enumerator(
        at: URL(fileURLWithPath: directory),
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        print("Error accessing directory")
        return []
    }
    
    for case let fileURL as URL in enumerator {
        guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
              let isRegularFile = resourceValues.isRegularFile,
              isRegularFile else {
            continue
        }
        
        let lineCount = countLines(in: fileURL.path)
        if lineCount > threshold {
            let relativePath = fileURL.path.replacingOccurrences(
                of: FileManager.default.currentDirectoryPath + "/",
                with: ""
            )
            results.append((relativePath, lineCount))
        }
    }
    
    return results.sorted { $0.1 > $1.1 }
}

// Main execution
let currentDirectory = FileManager.default.currentDirectoryPath
let results = findLargeFiles(in: currentDirectory, threshold: 400)

print("\nFiles with more than 400 lines:\n")
for (file, count) in results {
    print("\(file): \(count) lines")
}

if results.isEmpty {
    print("No files found with more than 400 lines.")
}
