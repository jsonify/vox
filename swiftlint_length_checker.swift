#!/usr/bin/swift

import Foundation

struct TypeInfo {
    let name: String
    let startLine: Int
    let bodyLength: Int
    let filePath: String
    let actualContent: [String]  // Store the actual content for verification
}

func stripComments(from line: String) -> String {
    let commentStart = line.range(of: "//")
    if let start = commentStart {
        return String(line[..<start.lowerBound]).trimmingCharacters(in: .whitespaces)
    }
    return line
}

func findTypes(in filePath: String) -> [TypeInfo] {
    guard let contents = try? String(contentsOfFile: filePath, encoding: .utf8) else {
        return []
    }
    
    var types: [TypeInfo] = []
    let lines = contents.components(separatedBy: .newlines)
    var inComment = false
    var currentType: (name: String, startLine: Int)?
    var bodyLines = 0
    var braceCount = 0
    var currentTypeContent: [String] = []
    
    for (index, line) in lines.enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        // Handle multi-line comments
        if trimmed.contains("/*") {
            inComment = true
            continue
        }
        if trimmed.contains("*/") {
            inComment = false
            continue
        }
        if inComment {
            continue
        }
        
        // Skip empty lines and single-line comments
        if trimmed.isEmpty || trimmed.hasPrefix("//") {
            continue
        }
        
        // Detect type declarations
        if currentType == nil {
            if trimmed.contains("class ") || trimmed.contains("struct ") || trimmed.contains("enum ") {
                let words = trimmed.components(separatedBy: .whitespaces)
                if let typeIndex = words.firstIndex(where: { $0 == "class" || $0 == "struct" || $0 == "enum" }),
                   typeIndex + 1 < words.count {
                    let name = words[typeIndex + 1].components(separatedBy: ":")[0]
                    currentType = (name: name, startLine: index + 1)
                }
            }
        }
        
        // Track type body
        if let _ = currentType {
            braceCount += trimmed.filter { $0 == "{" }.count
            braceCount -= trimmed.filter { $0 == "}" }.count
            
            if braceCount > 0 {
                // Only count non-empty, non-comment lines
                let strippedLine = stripComments(from: trimmed)
                if !strippedLine.isEmpty {
                    bodyLines += 1
                    currentTypeContent.append(line)
                }
            }
            
            // Type definition complete
            if braceCount == 0 && bodyLines > 0 {
                types.append(TypeInfo(
                    name: currentType!.name,
                    startLine: currentType!.startLine,
                    bodyLength: bodyLines - 1, // Subtract 1 to exclude the opening brace line
                    filePath: filePath,
                    actualContent: currentTypeContent
                ))
                currentType = nil
                bodyLines = 0
                currentTypeContent = []
            }
        }
    }
    
    return types
}

// Find all Swift files
let fileManager = FileManager.default
let currentDirectory = fileManager.currentDirectoryPath
let enumerator = fileManager.enumerator(
    at: URL(fileURLWithPath: currentDirectory),
    includingPropertiesForKeys: [.isRegularFileKey],
    options: [.skipsHiddenFiles]
)!

var allTypes: [TypeInfo] = []
let threshold = 400

print("\nAnalyzing Swift files for type body length...\n")

for case let fileURL as URL in enumerator {
    guard fileURL.pathExtension == "swift" else { continue }
    
    let types = findTypes(in: fileURL.path)
    for type in types {
        let relativePath = type.filePath.replacingOccurrences(
            of: currentDirectory + "/",
            with: ""
        )
        // Print all types with their line counts for debugging
        if type.bodyLength > 300 { // Show types approaching the limit
            print("\(relativePath):\(type.startLine): Type '\(type.name)' body spans \(type.bodyLength) lines")
        }
    }
    allTypes.append(contentsOf: types)
}

let violations = allTypes.filter { $0.bodyLength > threshold }

if violations.isEmpty {
    print("\nNo Swift types found exceeding \(threshold) lines (excluding comments and whitespace).")
} else {
    print("\nSwift types exceeding \(threshold) lines (excluding comments and whitespace):\n")
    for violation in violations.sorted(by: { $0.bodyLength > $1.bodyLength }) {
        let relativePath = violation.filePath.replacingOccurrences(
            of: currentDirectory + "/",
            with: ""
        )
        print("\(relativePath):\(violation.startLine): Type '\(violation.name)' body spans \(violation.bodyLength) lines")
    }
}
