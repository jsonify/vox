import Foundation

Logger.shared.info("Starting main.swift", component: "main")
Logger.shared.info("Vox CLI started", component: "main")
Logger.shared.info("About to call Vox.main()", component: "main")
Vox.main()
Logger.shared.info("Vox.main() completed", component: "main")
