//
//  DenonInputSource.swift
//  DenonVolume
//
//  Created by Tim Carr on 5/7/20.
//  Copyright © 2020 Solodigitalis. All rights reserved.
//

import Foundation

struct InputSourceSetting : DenonSetting {
    enum Input: String, CaseIterable {
        case bt
        case bd
        case cd
        case dvd
        case game
        case hdRadio
        case satCbl
        case spotify
        case tv
        case mplay
        case net
        case phono
        case tuner
        case usbIpod
        case aux1
        case aux2
        case aux3
        case aux4
        case aux5
        case aux6
        case aux7
        case unknown
    }
    let input: Input
    
    var code: String
    var displayLong: String
    var displayShort: String
    var isHidden: Bool {
        // these don't have z2 appended because if you hide them, they should be hidden for both main and zone 2
        get { UserDefaults.standard.bool(forKey: "\(self.input.rawValue).\(self.userDefaultsSuffixHidden)") }
        set { UserDefaults.standard.set(newValue, forKey: "\(self.input.rawValue).\(self.userDefaultsSuffixHidden)") }
    }
    private let userDefaultsSuffixShort = "inputSourceNameShort"
    private let userDefaultsSuffixLong = "inputSourceNameLong"
    private let userDefaultsSuffixHidden = "inputSourceHidden"
    private let isZone2: Bool

    init(input: Input, isZone2: Bool) {
        self.input = input
        self.isZone2 = isZone2
        
        switch input {
        case .aux1:
            self.code = isZone2 ? "Z2AUX1" : "SIAUX1"
            self.displayLong = "AUX1"
            self.displayShort = "AUX1"
        case .aux2:
            self.code = isZone2 ? "Z2AUX2" : "SIAUX2"
            self.displayLong = "AUX2"
            self.displayShort = "AUX2"
        case .aux3:
            self.code = isZone2 ? "Z2AUX3" : "SIAUX3"
            self.displayLong = "AUX3"
            self.displayShort = "AUX3"
        case .aux4:
            self.code = isZone2 ? "Z2AUX4" : "SIAUX4"
            self.displayLong = "AUX4"
            self.displayShort = "AUX4"
        case .aux5:
            self.code = isZone2 ? "Z2AUX5" : "SIAUX5"
            self.displayLong = "AUX5"
            self.displayShort = "AUX5"
        case .aux6:
            self.code = isZone2 ? "Z2AUX6" : "SIAUX6"
            self.displayLong = "AUX6"
            self.displayShort = "AUX6"
        case .aux7:
            self.code = isZone2 ? "Z2AUX7" : "SIAUX7"
            self.displayLong = "AUX7"
            self.displayShort = "AUX7"
        case .bd:
            self.code = isZone2 ? "Z2BD" : "SIBD"
            self.displayLong = "Blu-ray"
            self.displayShort = "BD"
        case .bt:
            self.code = isZone2 ? "Z2BT" : "SIBT"
            self.displayLong = "Bluetooth"
            self.displayShort = "BT"
        case .cd:
            self.code = isZone2 ? "Z2CD" : "SICD"
            self.displayLong = "CD"
            self.displayShort = "CD"
        case .dvd:
            self.code = isZone2 ? "Z2DVD" : "SIDVD"
            self.displayLong = "DVD"
            self.displayShort = "DVD"
        case .game:
            self.code = isZone2 ? "Z2GAME" : "SIGAME"
            self.displayLong = "Game Console"
            self.displayShort = "GAME"
        case .hdRadio:
            self.code = isZone2 ? "Z2HDRADIO" : "SIHDRADIO"
            self.displayLong = "HD Radio"
            self.displayShort = "RAD"
        case .satCbl:
            self.code = isZone2 ? "Z2SAT/CBL" : "SISAT/CBL"
            self.displayLong = "Satellite / Cable"
            self.displayShort = "CBL"
        case .tv:
            self.code = isZone2 ? "Z2TV" : "SITV"
            self.displayLong = "TV"
            self.displayShort = "TV"
        case .mplay:
            self.code = isZone2 ? "Z2MPLAY" : "SIMPLAY"
            self.displayLong = "Media player"
            self.displayShort = "MEDIA"
        case .net:
            self.code = isZone2 ? "Z2NET" : "SINET"
            self.displayLong = "Online Music"
            self.displayShort = "NET"
        case .phono:
            self.code = isZone2 ? "Z2PHONO" : "SIPHONO"
            self.displayLong = "Phono"
            self.displayShort = "PHN"
        case .tuner:
            self.code = isZone2 ? "Z2TUNER" : "SITUNER"
            self.displayLong = "Tuner"
            self.displayShort = "TUN"
        case .usbIpod:
            self.code = isZone2 ? "Z2USB/IPOD" : "SIUSB/IPOD"
            self.displayLong = "USB / iPod"
            self.displayShort = "USB"
        case .spotify:
            self.code = isZone2 ? "Z2SPOTIFY" : "SISPOTIFY"
            self.displayLong = "Spotify"
            self.displayShort = "SPO"
            self.isHidden = true
        case .unknown:
            self.code = "UNK"
            self.displayLong = "Unknown"
            self.displayShort = "UNK"
        }
        
        if let renamedShort = UserDefaults.standard.string(forKey: input.rawValue + "." + self.userDefaultsSuffixShort + (self.isZone2 ? "-z2" : "")), let renamedLong = UserDefaults.standard.string(forKey: input.rawValue + "." + self.userDefaultsSuffixLong + (self.isZone2 ? "-z2" : "")) {
            self.displayLong = renamedLong
            self.displayShort = renamedShort
        }
    }
    
    init?(str: String) {
        var hits = Input.allCases.map { InputSourceSetting.init(input: $0, isZone2: false) }.filter { $0.code == str }
        if hits.count == 1 {
            self.init(input: hits[0].input, isZone2: false)
            return
        }
        hits = Input.allCases.map { InputSourceSetting.init(input: $0, isZone2: true) }.filter { $0.code == str }
        guard hits.count == 1 else { return nil }
        self.init(input: hits[0].input, isZone2: true)
    }
    
    func rename(short: String, long: String) {
        UserDefaults.standard.set(short, forKey: self.input.rawValue + "." + self.userDefaultsSuffixShort + (self.isZone2 ? "-z2" : ""))
        UserDefaults.standard.set(long, forKey: self.input.rawValue + "." + self.userDefaultsSuffixLong + (self.isZone2 ? "-z2" : ""))
    }
    
    func setValue(denon: DenonController?, _ completionBlock: CommandNoResponseBlock = nil) {
        guard let denon = denon, let stream = denon.stream23 else { completionBlock?(CommandError.noDenon); return }
        denon.issueCommand(self.code, minLength: self.code.count, responseLineRegex: "\(self.code).*", stream: stream, timeoutBlock: {
            completionBlock?(.tryAgain)
        }) { (str, err) in
            guard let str = str else {
                completionBlock?(err ?? CommandError.noDataReturned)
                return
            }
            if str.hasPrefix(self.code) {
                completionBlock?(nil)
                return
            }
            completionBlock?(.dataReturnedNotUnderstood)
        }
    }
}
