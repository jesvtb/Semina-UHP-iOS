import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Darwin)
import Darwin
#endif

public enum LocalKokoroDeviceGateFailureReason: String, Sendable {
    case simulator
    case lowOSVersion
    case lowMemory
    case lowPowerMode
    case thermalCritical
}

public struct LocalKokoroDeviceGateResult: Sendable {
    public let isSupported: Bool
    public let failureReason: LocalKokoroDeviceGateFailureReason?

    public init(isSupported: Bool, failureReason: LocalKokoroDeviceGateFailureReason? = nil) {
        self.isSupported = isSupported
        self.failureReason = failureReason
    }
}

public enum LocalKokoroDeviceGate {
    public static let minimumAvailableMemoryBytes: UInt64 = 1_500 * 1024 * 1024

    public static func evaluate() -> LocalKokoroDeviceGateResult {
        #if targetEnvironment(simulator)
        return LocalKokoroDeviceGateResult(
            isSupported: false,
            failureReason: .simulator
        )
        #else
        if #unavailable(iOS 18.0) {
            return LocalKokoroDeviceGateResult(
                isSupported: false,
                failureReason: .lowOSVersion
            )
        }

        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            return LocalKokoroDeviceGateResult(
                isSupported: false,
                failureReason: .lowPowerMode
            )
        }

        #if canImport(UIKit)
        if ProcessInfo.processInfo.thermalState == .critical {
            return LocalKokoroDeviceGateResult(
                isSupported: false,
                failureReason: .thermalCritical
            )
        }
        #endif

        if let availableMemoryBytes = currentAvailableMemoryBytes(),
           availableMemoryBytes < minimumAvailableMemoryBytes {
            return LocalKokoroDeviceGateResult(
                isSupported: false,
                failureReason: .lowMemory
            )
        }

        return LocalKokoroDeviceGateResult(isSupported: true)
        #endif
    }

    public static func currentAvailableMemoryBytes() -> UInt64? {
        #if os(iOS)
        let availableBytes = os_proc_available_memory()
        return availableBytes > 0 ? UInt64(availableBytes) : nil
        #else
        return nil
        #endif
    }
}
