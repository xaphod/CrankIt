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
            DLog("HEOSHandler getPlayers() timeout, giving up")
        } _: { str, error in
            guard let str = str, let data = str.data(using: .utf8), let response = try? self.decoder.decode(PayloadResponse<HEOSPlayer>.self, from: data) else {
                assert(false)
                return
            }
            
            self.pid = response.payload.first?.pid as? Int
            guard let pid = self.pid else {
                return
            }
            DLog("HEOSHandler getPlayers() success, pid=\(pid)")
            
            self.updatePlayState(stream: stream)
        }
    }
    
    func updatePlayState(stream: DenonStreams) {
        guard let pid = self.pid else { return }
        self.dc.issueCommand("heos://player/get_now_playing_media?pid=\(pid)", minLength: 2, responseLineRegex: nil, stream: stream, readAfterWrite: false)
    }
    
    func parseResponseHelper(line: String.SubSequence) -> Bool {
        guard let data = String(line).data(using: .utf8), let base = try? decoder.decode(HEOSRoot.self, from: data) else {
            DLog("DenonHEOSHandler: WARNING, not understood: \(line)")
            return false
        }

        DLog("HEOSHandler parseResponseHelper: command=\(base.heos.command) message=\(base.heos.message)")
        return true
    }
}
