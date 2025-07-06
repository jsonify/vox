import Foundation

// Only execute main logic when running as an executable, not during test imports
if !CommandLine.arguments.isEmpty && CommandLine.arguments[0].contains("vox") {
    Logger.shared.info("Starting main.swift", component: "main")
    Logger.shared.info("Vox CLI started", component: "main")
    Logger.shared.info("About to call Vox.main()", component: "main")
    Vox.main()
    Logger.shared.info("Vox.main() completed", component: "main")
}
