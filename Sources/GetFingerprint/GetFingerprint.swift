import Foundation
import IOKit

@main
struct GetFingerprint {
    static func main() {
        guard let uuid = readIOPlatformUUID() else {
            fputs("error: Could not read IOPlatformUUID from this device.\n", stderr)
            exit(1)
        }
        print(uuid)
    }
}

private func readIOPlatformUUID() -> String? {
    let matching = IOServiceMatching("IOPlatformExpertDevice")
    let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
    defer { IOObjectRelease(service) }
    guard service != 0 else { return nil }
    let key = "IOPlatformUUID" as CFString
    let value = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0)
    return value?.takeRetainedValue() as? String
}
