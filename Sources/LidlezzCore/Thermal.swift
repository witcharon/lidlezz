import Foundation
import IOKit

private typealias HIDRef = CFTypeRef

@_silgen_name("IOHIDEventSystemClientCreate") private func IOHIDEventSystemClientCreate(_ a: CFAllocator?) -> HIDRef
@_silgen_name("IOHIDEventSystemClientSetMatching") private func IOHIDEventSystemClientSetMatching(_ c: HIDRef, _ m: CFDictionary) -> Int32
@_silgen_name("IOHIDEventSystemClientCopyServices") private func IOHIDEventSystemClientCopyServices(_ c: HIDRef) -> CFArray?
@_silgen_name("IOHIDServiceClientCopyProperty") private func IOHIDServiceClientCopyProperty(_ s: HIDRef, _ k: CFString) -> CFTypeRef?
@_silgen_name("IOHIDServiceClientCopyEvent") private func IOHIDServiceClientCopyEvent(_ s: HIDRef, _ t: Int64, _ o: Int32, _ ts: Int64) -> HIDRef?
@_silgen_name("IOHIDEventGetFloatValue") private func IOHIDEventGetFloatValue(_ e: HIDRef, _ f: Int32) -> Double

/// Apple Silicon temperature sensors through the HID event system. No root needed.
public enum Thermal {
    private static let temperatureEvent: Int64 = 15
    private static let client: HIDRef = {
        let c = IOHIDEventSystemClientCreate(kCFAllocatorDefault)
        let match: [String: Any] = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5]
        _ = IOHIDEventSystemClientSetMatching(c, match as CFDictionary)
        return c
    }()

    public static func sensors() -> [(name: String, celsius: Double)] {
        guard let services = IOHIDEventSystemClientCopyServices(client) as? [HIDRef] else { return [] }
        return services.compactMap { s in
            guard let event = IOHIDServiceClientCopyEvent(s, temperatureEvent, 0, 0) else { return nil }
            let name = (IOHIDServiceClientCopyProperty(s, "Product" as CFString) as? String) ?? "?"
            return (name, IOHIDEventGetFloatValue(event, Int32(temperatureEvent << 16)))
        }
    }

    /// Hottest CPU/GPU die sensor.
    /// Hottest die sensor. M2 and later expose "PMU tdie…"; M1 exposes "pACC/eACC MTR Temp Sensor…".
    public static func socCelsius() -> Double? {
        let all = sensors()
        let die = all.filter { $0.name.contains("tdie") }
        let cores = all.filter { $0.name.contains("ACC MTR Temp Sensor") }
        return (die.isEmpty ? cores : die).map(\.celsius).max()
    }
}
