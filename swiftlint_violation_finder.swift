#!/usr/bin/swift

import Foundation

struct SwiftLintViolation {
    let file: String
    let line: Int
    let column: Int
    let severity: String
    let rule: String
    let message: String
    
    var description: String {
        let emoji = severity == "error" ? "❌" : "⚠️"
        return "\(emoji) \(file):\(line):\(column) - \(rule)\n   \(message)"
    }
}

func parseSwiftLintOutput() -> [SwiftLintViolation] {
    let task = Process()
    task.launchPath = "/usr/bin/env"
    task.arguments = ["swiftlint", "lint", "--quiet"]
    
    let pipe = Pipe()
    task.standardOutput = pipe
    task.launch()
    task.waitUntilExit()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else {
        return []
    }
    
    var violations: [SwiftLintViolation] = []
    
    for line in output.components(separatedBy: .newlines) {
        if line.isEmpty { continue }
        
        // Parse format: ::severity file=path,line=num,col=num::message (rule)
        let pattern = #"::(\w+) file=([^,]+),line=(\d+),col=(\d+)::(.+) \((\w+)\)"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.count)) else {
            continue
        }
        
        let severity = String(line[Range(match.range(at: 1), in: line)!])
        let file = String(line[Range(match.range(at: 2), in: line)!])
        let lineNum = Int(String(line[Range(match.range(at: 3), in: line)!])) ?? 0
        let column = Int(String(line[Range(match.range(at: 4), in: line)!])) ?? 0
        let message = String(line[Range(match.range(at: 5), in: line)!])
        let rule = String(line[Range(match.range(at: 6), in: line)!])
        
        violations.append(SwiftLintViolation(
            file: file,
            line: lineNum,
            column: column,
            severity: severity,
            rule: rule,
            message: message
        ))
    }
    
    return violations
}

func groupViolationsByRule(_ violations: [SwiftLintViolation]) -> [String: [SwiftLintViolation]] {
    return Dictionary(grouping: violations) { $0.rule }
}

func printViolationSummary(_ violations: [SwiftLintViolation]) {
    let errors = violations.filter { $0.severity == "error" }
    let warnings = violations.filter { $0.severity == "warning" }
    
    print("🔍 SwiftLint Violation Summary")
    print("═══════════════════════════════")
    print("Total violations: \(violations.count)")
    print("Errors: \(errors.count)")
    print("Warnings: \(warnings.count)")
    print("")
    
    if violations.isEmpty {
        print("✅ No SwiftLint violations found!")
        return
    }
    
    let groupedViolations = groupViolationsByRule(violations)
    
    // Print errors first
    if !errors.isEmpty {
        print("❌ ERRORS (will block CI/commits):")
        print("══════════════════════════════════")
        
        for rule in groupedViolations.keys.sorted() {
            let ruleErrors = groupedViolations[rule]?.filter { $0.severity == "error" } ?? []
            if !ruleErrors.isEmpty {
                print("\n📋 Rule: \(rule) (\(ruleErrors.count) errors)")
                print("─────────────────────────────")
                for violation in ruleErrors {
                    print(violation.description)
                }
                
                // Provide specific fix suggestions
                print("\n💡 Fix suggestions for \(rule):")
                switch rule {
                case "type_body_length":
                    print("   • Split large classes/structs into smaller, focused components")
                    print("   • Extract related functionality into separate files")
                    print("   • Use composition over inheritance to reduce complexity")
                case "empty_count":
                    print("   • Replace '.count > 0' with '!.isEmpty'")
                    print("   • Replace '.count == 0' with '.isEmpty'")
                    print("   • Use isEmpty for better performance and readability")
                default:
                    print("   • Check SwiftLint documentation for rule '\(rule)'")
                }
            }
        }
        print("")
    }
    
    // Print warnings
    if !warnings.isEmpty {
        print("⚠️  WARNINGS (recommended fixes):")
        print("═════════════════════════════════")
        
        for rule in groupedViolations.keys.sorted() {
            let ruleWarnings = groupedViolations[rule]?.filter { $0.severity == "warning" } ?? []
            if !ruleWarnings.isEmpty {
                print("\n📋 Rule: \(rule) (\(ruleWarnings.count) warnings)")
                print("─────────────────────────────")
                for violation in ruleWarnings.prefix(5) { // Limit to first 5 to avoid spam
                    print(violation.description)
                }
                if ruleWarnings.count > 5 {
                    print("   ... and \(ruleWarnings.count - 5) more")
                }
            }
        }
    }
    
    print("\n🔧 Quick Commands:")
    print("─────────────────")
    print("• Run pre-commit check: .git/hooks/pre-commit")
    print("• Fix auto-fixable issues: swiftlint --fix")
    print("• Check specific rule: swiftlint lint --quiet | grep '<rule_name>'")
    
    if !errors.isEmpty {
        print("\n🚫 Commit Status: BLOCKED (fix errors first)")
        exit(1)
    } else {
        print("\n✅ Commit Status: ALLOWED (warnings are non-blocking)")
        exit(0)
    }
}

// Main execution
let violations = parseSwiftLintOutput()
printViolationSummary(violations)