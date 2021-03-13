//
//  DenonReceiver.swift
//  DenonVolume
//
//  Created by Tim Carr on 5/4/20.
//  Copyright © 2020 Solodigitalis. All rights reserved.
//

import Foundation

// Used by discovery. Note that the parser does NOT expect the top-level <root> to be included here
struct Receiver : Codable {
    var worksWithCrankIt: Bool {
        self.device.manufacturer.caseInsensitiveCompare("Denon") == .orderedSame
        || self.device.manufacturer.caseInsensitiveCompare("Marantz") == .orderedSame
    }
    var description: String { "\(self.device.friendlyName ?? self.device.manufacturer) - \(self.device.modelNumber ?? self.device.modelName ?? self.device.modelDescription ?? self.ipAddress ?? "n/a")" }
    var ipAddress: String?
    
    struct Device: Codable {
        let friendlyName: String? // Living Room
        let manufacturer: String // Denon
        let modelDescription: String? // AV SURROUND RECEIVER
        let modelName: String? // *AVR-X3300W
        let modelNumber: String? // X3300W
    }
    let device: Device
}
