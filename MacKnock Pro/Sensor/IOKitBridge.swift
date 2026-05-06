// IOKitBridge.swift
// MacKnock Pro
//
// Low-level IOKit HID bridge for reading the Apple Silicon MEMS
// accelerometer (Bosch BMI286 IMU via AppleSPUHIDDevice).
// Ported from: https://github.com/olvvier/apple-silicon-accelerometer

import Foundation
import IOKit
import IOKit.hid

// MARK: - Constants

/// HID usage pages & usages for the SPU sensors
enum SPUConstants {
    /// Apple vendor HID usage page
    static let pageVendor: UInt32 = 0xFF00
    /// HID sensor usage page
    static let pageSensor: UInt32 = 0x0020
    /// Accelerometer usage ID
    static let usageAccel: UInt32 = 3
    /// Gyroscope usage ID
    static let usageGyro: UInt32 = 9
    /// Ambient light sensor usage ID
    static let usageALS: UInt32 = 4
    /// Lid angle sensor usage ID
    static let usageLid: UInt32 = 138
    
    /// IMU HID report length (22 bytes for BMI286)
    static let imuReportLength: Int = 22
    /// Byte offset where XYZ data starts in the report
    static let imuDataOffset: Int = 6
    /// HID callback report buffer size
    static let reportBufferSize: Int = 4096
    /// Driver report interval in microseconds
    static let reportIntervalUS: Int32 = 1000
    
    /// Scaling factor: Q16 raw → g (accelerometer)
    static let accelScale: Double = 65536.0
    /// Scaling factor: Q16 raw → deg/s (gyroscope)
    static let gyroScale: Double = 65536.0
    
    /// Default decimation factor (keep 1 in N reports, ~100Hz from ~800Hz)
    static let defaultDecimation: Int = 8
}

// MARK: - IOKit Bridge

/// Provides low-level IOKit HID access to the Apple Silicon MEMS accelerometer
final class IOKitBridge {
    
    /// Check if the SPU accelerometer sensor is present (no root needed)
    static func isAccelerometerAvailable() -> Bool {
        let matching = IOServiceMatching("AppleSPUHIDDevice") as NSDictionary as CFDictionary
        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        
        guard kr == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iterator) }
        
        var found = false
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let usagePage = getIntProperty(service: service, key: "PrimaryUsagePage")
            let usage = getIntProperty(service: service, key: "PrimaryUsage")
            
            if usagePage == Int(SPUConstants.pageVendor) && usage == Int(SPUConstants.usageAccel) {
                found = true
            }
            IOObjectRelease(service)
            if found { break }
            service = IOIteratorNext(iterator)
        }
        
        // Release remaining services
        while service != 0 {
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        
        return found
    }
    
    /// Get device info for all SPU sensors (no root needed)
    static func getDeviceInfo() -> [String: Any] {
        var info: [String: Any] = ["sensors": [String]()]
        let usageNames: [(UInt32, UInt32, String)] = [
            (SPUConstants.pageVendor, SPUConstants.usageAccel, "accelerometer"),
            (SPUConstants.pageVendor, SPUConstants.usageGyro, "gyroscope"),
            (SPUConstants.pageVendor, SPUConstants.usageALS, "ambient_light"),
            (SPUConstants.pageSensor, SPUConstants.usageLid, "lid_angle"),
        ]
        
        let matching = IOServiceMatching("AppleSPUHIDDevice") as NSDictionary as CFDictionary
        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == KERN_SUCCESS else { return info }
        defer { IOObjectRelease(iterator) }
        
        var sensors = [String]()
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let up = UInt32(getIntProperty(service: service, key: "PrimaryUsagePage") ?? 0)
            let u = UInt32(getIntProperty(service: service, key: "PrimaryUsage") ?? 0)
            
            for (page, usage, name) in usageNames {
                if up == page && u == usage {
                    sensors.append(name)
                }
            }
            
            // Read additional properties
            for key in ["Product", "SerialNumber", "Manufacturer", "Transport"] {
                if let val = getStringProperty(service: service, key: key) {
                    info[key] = val
                }
            }
            for key in ["VendorID", "ProductID"] {
                if let val = getIntProperty(service: service, key: key) {
                    info[key] = val
                }
            }
            
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        
        info["sensors"] = sensors
        return info
    }
    
    // MARK: - Property Helpers
    
    private static func getIntProperty(service: io_service_t, key: String) -> Int? {
        guard let cfProp = IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else { return nil }
        
        if let number = cfProp as? NSNumber {
            return number.intValue
        }
        return nil
    }
    
    private static func getStringProperty(service: io_service_t, key: String) -> String? {
        guard let cfProp = IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else { return nil }
        
        return cfProp as? String
    }
    
    private static func setIntProperty(service: io_service_t, key: String, value: Int32) {
        let cfValue = NSNumber(value: value) as CFNumber
        IORegistryEntrySetCFProperty(service, key as CFString, cfValue)
    }
    
    // MARK: - SPU Driver Wake
    
    /// Wake the SPU drivers by setting reporting state, power state, and report interval.
    /// This must be called before HID devices will produce data.
    static func wakeSPUDrivers() {
        let matching = IOServiceMatching("AppleSPUHIDDriver") as NSDictionary as CFDictionary
        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        
        var service = IOIteratorNext(iterator)
        while service != 0 {
            setIntProperty(service: service, key: "SensorPropertyReportingState", value: 1)
            setIntProperty(service: service, key: "SensorPropertyPowerState", value: 1)
            setIntProperty(service: service, key: "ReportInterval", value: SPUConstants.reportIntervalUS)
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }
    
    // MARK: - HID Device Access
    
    /// Open the accelerometer HID device and register a callback for input reports.
    /// Returns the IOHIDDevice reference (must keep alive) and the report buffer.
    /// Requires root privileges.
    static func openAccelerometer(
        callback: @escaping IOHIDReportWithTimeStampCallback,
        context: UnsafeMutableRawPointer?
    ) -> (device: IOHIDDevice, reportBuffer: UnsafeMutablePointer<UInt8>)? {
        let matching = IOServiceMatching("AppleSPUHIDDevice") as NSDictionary as CFDictionary
        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let up = UInt32(getIntProperty(service: service, key: "PrimaryUsagePage") ?? 0)
            let u = UInt32(getIntProperty(service: service, key: "PrimaryUsage") ?? 0)
            
            if up == SPUConstants.pageVendor && u == SPUConstants.usageAccel {
                // Found the accelerometer device
                guard let hidDevice = IOHIDDeviceCreate(kCFAllocatorDefault, service) else {
                    IOObjectRelease(service)
                    service = IOIteratorNext(iterator)
                    continue
                }
                
                let device = hidDevice as IOHIDDevice
                let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
                
                if openResult == kIOReturnSuccess {
                    // Allocate report buffer
                    let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(
                        capacity: SPUConstants.reportBufferSize
                    )
                    reportBuffer.initialize(repeating: 0, count: SPUConstants.reportBufferSize)
                    
                    // Register timestamped input report callback
                    IOHIDDeviceRegisterInputReportWithTimeStampCallback(
                        device,
                        reportBuffer,
                        CFIndex(SPUConstants.reportBufferSize),
                        callback,
                        context
                    )
                    
                    // Schedule with the current run loop
                    IOHIDDeviceScheduleWithRunLoop(
                        device,
                        CFRunLoopGetCurrent(),
                        CFRunLoopMode.defaultMode.rawValue
                    )
                    
                    IOObjectRelease(service)
                    
                    // Release remaining
                    service = IOIteratorNext(iterator)
                    while service != 0 {
                        IOObjectRelease(service)
                        service = IOIteratorNext(iterator)
                    }
                    
                    return (device, reportBuffer)
                }
            }
            
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        
        return nil
    }
    
    /// Parse a 22-byte IMU HID report into raw int32 x/y/z values.
    /// Returns nil if the report length doesn't match.
    static func parseIMUReport(
        report: UnsafePointer<UInt8>,
        length: Int
    ) -> (x: Int32, y: Int32, z: Int32)? {
        guard length == SPUConstants.imuReportLength else { return nil }
        
        let offset = SPUConstants.imuDataOffset
        
        // Manually assemble little-endian Int32 from individual bytes.
        // Both withMemoryRebound and UnsafeRawPointer.load enforce alignment
        // on arm64, but HID report offsets 6, 10, 14 are NOT 4-byte aligned.
        @inline(__always)
        func readLE32(_ p: UnsafePointer<UInt8>, _ off: Int) -> Int32 {
            let b0 = Int32(p[off])
            let b1 = Int32(p[off + 1]) << 8
            let b2 = Int32(p[off + 2]) << 16
            let b3 = Int32(p[off + 3]) << 24
            return b0 | b1 | b2 | b3
        }
        
        let x = readLE32(report, offset)
        let y = readLE32(report, offset + 4)
        let z = readLE32(report, offset + 8)
        
        return (x, y, z)
    }
    
    /// Convert mach_absolute_time to seconds using timebase info
    static let machToSeconds: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) * 1e-9
    }()
}
