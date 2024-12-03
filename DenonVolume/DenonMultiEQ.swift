//
//  DenonMultiEQ.swift
//  DenonVolume
//
//  Created by Tim Carr on 5/7/20.
//  Copyright © 2020 Solodigitalis. All rights reserved.
//

import Foundation

struct MultiEQSetting : DenonSetting {
    enum MultiEQ: String, CaseIterable {
        case off
        case manual
        case flat
        case bypassLR
        case audyssey
    }
    let eq: MultiEQ
    
    let code: String
    let displayLong: String
    let displayShort: String
    static var values: [MultiEQSetting] {
        return MultiEQ.allCases.map { MultiEQSetting.init(eq: $0) }
    }

    init(eq: MultiEQ) {
        self.eq = eq
        switch eq {
        case .audyssey:
            self.code = "PSMULTEQ:AUDYSSEY"
            self.displayLong = "Audyssey"
            self.displayShort = "AUD"
        case .bypassLR:
            self.code = "PSMULTEQ:BYP.LR"
            self.displayLong = "Bypass L/R"
            self.displayShort = "BYP"
        case .flat:
            self.code = "PSMULTEQ:FLAT"
            self.displayLong = "Audyssey Flat"
            self.displayShort = "AUDF"
        case .manual:
            self.code = "PSMULTEQ:MANUAL"
            self.displayLong = "Manual"
            self.displayShort = "MAN"
        case .off:
            self.code = "PSMULTEQ:OFF"
            self.displayLong = "Audyssey off"
            self.displayShort = "OFF"
        }
    }
    
    init?(str: String) {
        let hits = MultiEQSetting.values.filter { $0.code == str }
        guard hits.count == 1 else { return nil }
        self.init(eq: hits[0].eq)
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
