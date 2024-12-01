//
//  CommandResponse.swift
//  DenonVolume
//
//  Created by Tim Carr on 2024-12-01.
//  Copyright © 2024 Solodigitalis. All rights reserved.
//

import Foundation

// the value after "heos".

// Example: we sent a get_players command
// "{\"heos\": {\"command\": \"player/get_players\", \"result\": \"success\", \"message\": \"\"}, \"payload\": [{\"name\": \"Denon AVR-X3600H\", \"pid\": -1320513458, \"model\": \"Denon AVR-X3600H\", \"version\": \"3.34.410\", \"ip\": \"192.168.1.218\", \"network\": \"wifi\", \"lineout\": 0, \"serial\": \"BHA36190806276\"}]}\r\n"

// Example: someone (not us) changed the volume
// {"heos": {"command": "event/player_volume_changed", "message": "pid=-1320513458&level=40&mute=off"}}

struct HEOSRoot : Codable {
    var heos: HEOSCommand
}

struct HEOSCommand : Codable {
    var command: String // what
    var message: String
}

enum HEOSCommandResponseResult : String, Codable {
    case success
    case fail
}

struct HEOSCommandResponse : Codable {
    var command: String // what
    var message: String
    var result: HEOSCommandResponseResult
}
