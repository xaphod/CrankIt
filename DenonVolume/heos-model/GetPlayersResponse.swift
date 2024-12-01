//
//  GetPlayersResponse.swift
//  DenonVolume
//
//  Created by Tim Carr on 2024-12-01.
//  Copyright © 2024 Solodigitalis. All rights reserved.
//

// heos://player/get_players
// {"heos": {"command": "player/get_players", "result": "success", "message": ""}, "payload": [{"name": "Denon AVR-X3600H", "pid": -1320513458, "model": "Denon AVR-X3600H", "version": "3.34.410", "ip": "192.168.1.218", "network": "wifi", "lineout": 0, "serial": "BHA36190806276"}]}


struct GetPlayersResponse : Codable {
    var payload: [HEOSPlayer]
}
