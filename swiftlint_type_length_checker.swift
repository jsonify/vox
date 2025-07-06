#!/usr/bin/swift

import Foundation

struct TypeInfo {
    let name: String
    let startLine: Int
    let bodyLength: Int
    let filePath: String
}

func isComment(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    return trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") || trimmed.hasSuffix("*/")
}

func findTypeBodyLength(in filePath: String) -> [TypeInfo] {
    guard let contents = try? String(contentsOfFile: filePath, encoding: .utf8) else {
        return []
    }
    
    var types: [TypeInfo] = []
    let lines = contents.components(separatedBy: .newlines)
    var inComment = false
    var currentType: (name: String, startLine: Int)?
    var braceCount = 0
    var nonBlankCount = 0
    
    for (index, line) in lines.enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        // Handle multi-line comments
        if trimmed.contains("/*") && !trimmed.contains("*/") {
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
        
        // Skip single-line comments and empty lines
        if isComment(line) || trimmed.isEmpty {
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
                    braceCount = 0
                    nonBlankCount = 0
                }
            }
        }
        
        // Count braces to track type body
        if currentType != nil {
            braceCount += trimmed.filter { $0 == "{" }.count
            braceCount -= trimmed.filter { $0 == "}" }.count
            
            if braceCount > 0 {
                nonBlankCount += 1
            }
            
            // Type definition complete
            if braceCount == 0 && nonBlankCount > 0 {
                types.append(TypeInfo(
                    name: currentType!.name,
                    startLine: currentType!.startLine,
                    bodyLength: nonBlankCount - 1, // Subtract 1 to match SwiftLint's counting
                    filePath: filePath
                ))
                currentType = nil
            }
        }
    }
    
    return types
}

print("\nChecking Swift files for type body length...\n")

let fileManager = FileManager.default
let currentDirectory = fileManager.currentDirectoryPath
let enumerator = fileManager.enumerator(
    at: URL(fileURLWithPath: currentDirectory),
    includingPropertiesForKeys: [.isRegularFileKey],
    options: [.skipsHiddenFiles]
)!

for case let fileURL as URL in enumerator {
    guard fileURL.pathExtension == "swift" else { continue }
    
    let types = findTypeBodyLength(in: fileURL.path)
    for type in types {
        if type.bodyLength > 350 { // Show types approaching or exceeding the limit
            let relativePath = type.filePath.replacingOccurrences(
                of: currentDirectory + "/",
                with: ""
            )
            print("\(relativePath):\(type.startLine): Type '\(type.name)' body spans \(type.bodyLength) lines")
        }
    }
}
