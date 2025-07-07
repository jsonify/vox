import Foundation

// Temporary main for debugging
if #available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *) {
    print("Starting Vox...")
    Vox.main()
} else {
    print("Error: Vox requires macOS 10.15 or later for async support")
    exit(1)
}