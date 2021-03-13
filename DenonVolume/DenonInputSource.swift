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
        get { UserDefaults.standard.bool(forKey: "\(self.input.rawValue).\(self.userDefaultsSuffixHidden)") }
        set { UserDefaults.standard.set(newValue, forKey: "\(self.input.rawValue).\(self.userDefaultsSuffixHidden)") }
    }
    static var values: [InputSourceSetting] {
        return Input.allCases.map { InputSourceSetting.init(input: $0) }
    }
    private let userDefaultsSuffixShort = "inputSourceNameShort"
    private let userDefaultsSuffixLong = "inputSourceNameLong"
    private let userDefaultsSuffixHidden = "inputSourceHidden"

    init(input: Input) {
        self.input = input
        
        switch input {
        case .aux1:
            self.code = "SIAUX1"
            self.displayLong = "AUX1"
            self.displayShort = "AUX1"
        case .aux2:
            self.code = "SIAUX2"
            self.displayLong = "AUX2"
            self.displayShort = "AUX2"
        case .aux3:
            self.code = "SIAUX3"
            self.displayLong = "AUX3"
            self.displayShort = "AUX3"
        case .aux4:
            self.code = "SIAUX4"
            self.displayLong = "AUX4"
            self.displayShort = "AUX4"
        case .aux5:
            self.code = "SIAUX5"
            self.displayLong = "AUX5"
            self.displayShort = "AUX5"
        case .aux6:
            self.code = "SIAUX6"
            self.displayLong = "AUX6"
            self.displayShort = "AUX6"
        case .aux7:
            self.code = "SIAUX7"
            self.displayLong = "AUX7"
            self.displayShort = "AUX7"
        case .bd:
            self.code = "SIBD"
            self.displayLong = "Blu-ray"
            self.displayShort = "BD"
        case .bt:
            self.code = "SIBT"
            self.displayLong = "Bluetooth"
            self.displayShort = "BT"
        case .cd:
            self.code = "SICD"
            self.displayLong = "CD"
            self.displayShort = "CD"
        case .dvd:
            self.code = "SIDVD"
            self.displayLong = "DVD"
            self.displayShort = "DVD"
        case .game:
            self.code = "SIGAME"
            self.displayLong = "Game Console"
            self.displayShort = "GAME"
        case .hdRadio:
            self.code = "SIHDRADIO"
            self.displayLong = "HD Radio"
            self.displayShort = "RAD"
        case .satCbl:
            self.code = "SISAT/CBL"
            self.displayLong = "Satellite / Cable"
            self.displayShort = "CBL"
        case .tv:
            self.code = "SITV"
            self.displayLong = "TV"
            self.displayShort = "TV"
        case .mplay:
            self.code = "SIMPLAY"
            self.displayLong = "Media player"
            self.displayShort = "MEDIA"
        case .net:
            self.code = "SINET"
            self.displayLong = "Online Music"
            self.displayShort = "NET"
        case .phono:
            self.code = "SIPHONO"
            self.displayLong = "Phono"
            self.displayShort = "PHN"
        case .tuner:
            self.code = "SITUNER"
            self.displayLong = "Tuner"
            self.displayShort = "TUN"
        case .usbIpod:
            self.code = "SIUSB/IPOD"
            self.displayLong = "USB / iPod"
            self.displayShort = "USB"
        case .spotify:
            self.code = "SISPOTIFY"
            self.displayLong = "Spotify"
            self.displayShort = "SPO"
            self.isHidden = true
        case .unknown:
            self.code = "UNK"
            self.displayLong = "Unknown"
            self.displayShort = "UNK"
        }
        
        if let renamedShort = UserDefaults.standard.string(forKey: input.rawValue + "." + self.userDefaultsSuffixShort), let renamedLong = UserDefaults.standard.string(forKey: input.rawValue + "." + self.userDefaultsSuffixLong) {
            self.displayLong = renamedLong
            self.displayShort = renamedShort
        }
    }
    
    init?(str: String) {
        let hits = InputSourceSetting.values.filter { $0.code == str }
        guard hits.count == 1 else { return nil }
        self.init(input: hits[0].input)
    }
    
    func rename(short: String, long: String) {
        UserDefaults.standard.set(short, forKey: self.input.rawValue + "." + self.userDefaultsSuffixShort)
        UserDefaults.standard.set(long, forKey: self.input.rawValue + "." + self.userDefaultsSuffixLong)
    }
    
    func setValue(denon: DenonController?, _ completionBlock: CommandNoResponseBlock = nil) {
        guard let denon = denon else { completionBlock?(CommandError.noDenon); return }
        denon.issueCommand(self.code, minLength: self.code.count, responseLineRegex: "\(self.code).*", timeoutBlock: {
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
