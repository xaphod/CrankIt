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
            guard let str = str, let data = str.data(using: .utf8), let response = try? self.decoder.decode(PayloadArrayResponse<HEOSPlayer>.self, from: data) else {
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
            // could be a partial line that we get more from & complete later
            // probably want to remove this log line when that's confirmed
            DLog("DenonHEOSHandler: WARNING, could not decode root: \(line)")
            return false
        }
        
        switch base.heos.command {
        case "player/get_now_playing_media":
            if let nowPlaying = (try? decoder.decode(PayloadSingleResponse<NowPlayingMedia>.self, from: data))?.payload {
                var userInfo: [AnyHashable : Any] = [
                    NowPlayingMediaNotificationKeys.song: nowPlaying.song ?? nowPlaying.station ?? "Unknown",
                    NowPlayingMediaNotificationKeys.artist: nowPlaying.artist,
                ]
                if let urlStr = nowPlaying.image_url, let url = URL.init(string: urlStr) {
                    userInfo[NowPlayingMediaNotificationKeys.mediaUrl] = url
                }
                if let album = nowPlaying.album {
                    userInfo[NowPlayingMediaNotificationKeys.album] = album
                }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .nowPlayingChanged, object: nil, userInfo: userInfo)
                }
            }
            
        default:
            DLog("DenonHEOSHandler: \(base.heos.command) is not yet handled")
        }

        // always return true - we received the complete struct
        return true
    }
}

extension Notification.Name {
    static let nowPlayingChanged = Notification.Name.init(rawValue: "now-playing-changed")
}
