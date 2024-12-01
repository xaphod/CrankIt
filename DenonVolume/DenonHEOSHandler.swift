//
//  DenonHEOSHandler.swift
//  DenonVolume
//
//  Created by Tim Carr on 2024-12-01.
//  Copyright © 2024 Solodigitalis. All rights reserved.
//

import Foundation

class DenonHEOSHandler {
    let decoder = JSONDecoder.init()
    var dc: DenonController!
    var pid: Int?
    
    init(dc: DenonController) {
        self.dc = dc
    }
    
    func heosStreamConnected(stream: DenonStreams) {
        DLog("heosStreamConnected()")
        self.getPlayers(stream: stream)
    }
    
    func getPlayers(stream: DenonStreams) {
        self.dc.issueCommand("heos://player/get_players", minLength: 1, responseLineRegex: nil, stream: stream) {
            DLog("getInitialHEOSState() timeout, no-op")
        } _: { str, error in
            guard let str = str, let data = str.data(using: .utf8), let response = try? self.decoder.decode(GetPlayersResponse.self, from: data) else {
                assert(false)
                return
            }
            
            self.pid = response.payload.first?.pid as? Int
            if let pid = self.pid {
                DLog("HEOSHandler got pid=\(pid)")
            }
        }
    }
    
    func getBase(_ str: String) -> HEOSBase? {
        guard let data = str.data(using: .utf8), let base = try? decoder.decode(HEOSBase.self, from: data) else {
            DLog("DenonHEOSHandler getBase: WARNING, not understood: \(str)")
            return nil
        }
        
        DLog("**** HEOS getBase command\(base.command) message=\(base.message)")
        return base
    }
    
    func parseResponseHelper(line: String.SubSequence) -> Bool {
        guard let data = String(line).data(using: .utf8), let base = try? decoder.decode(HEOSBase.self, from: data) else {
            DLog("DenonHEOSHandler: WARNING, not understood: \(line)")
            return false
        }
        
        DLog("**** HEOS command\(base.command) message=\(base.message)")
        
        return true
    }
}
