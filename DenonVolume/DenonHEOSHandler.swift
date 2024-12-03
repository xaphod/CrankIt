//
//  DenonHEOSHandler.swift
//  DenonVolume
//
//  Created by Tim Carr on 2024-12-01.
//  Copyright © 2024 Solodigitalis. All rights reserved.
//

import Foundation

class DenonHEOSHandler {
    enum PlayState : String {
        case pause
        case play
        case stop
    }
    var playState = PlayState.pause
    
    let decoder = JSONDecoder.init()
    var dc: DenonController!
    var pid: Int?
    private var didRegisterChangeEvents = false
    
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
            
            self.getNowPlayingMedia(stream: stream)
        }
    }
    
    func getNowPlayingMedia(stream: DenonStreams) {
        guard let pid = self.pid else { return }
        self.dc.issueCommand("heos://player/get_now_playing_media?pid=\(pid)", minLength: 2, responseLineRegex: nil, stream: stream, readAfterWrite: false)
    }
    
    func playPrevious(stream: DenonStreams) {
        guard let pid = self.pid else { return }
        self.dc.issueCommand("heos://player/play_previous?pid=\(pid)", minLength: 2, responseLineRegex: nil, stream: stream)
    }
    
    func playNext(stream: DenonStreams) {
        guard let pid = self.pid else { return }
        self.dc.issueCommand("heos://player/play_next?pid=\(pid)", minLength: 2, responseLineRegex: nil, stream: stream)
    }
    
    func setPlay(stream: DenonStreams) {
        guard let pid = self.pid else { return }
        self.dc.issueCommand("heos://player/set_play_state?pid=\(pid)&state=play", minLength: 2, responseLineRegex: nil, stream: stream)
    }

    func setPause(stream: DenonStreams) {
        guard let pid = self.pid else { return }
        self.dc.issueCommand("heos://player/set_play_state?pid=\(pid)&state=pause", minLength: 2, responseLineRegex: nil, stream: stream)
    }

    func parseResponseHelper(line: String.SubSequence, stream: DenonStreams) -> Bool {
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
                if !didRegisterChangeEvents {
                    didRegisterChangeEvents = true
                    self.dc.issueCommand("heos://system/register_for_change_events?enable=on", minLength: 1, responseLineRegex: nil, stream: stream, readAfterWrite: false)
                }
            }

        case "system/register_for_change_events":
            guard let pid = self.pid else { return true }
            self.dc.issueCommand("heos://player/get_play_state?pid=\(pid)", minLength: 1, responseLineRegex: nil, stream: stream, readAfterWrite: false)

        case "event/player_state_changed", "player/get_play_state":
            /*
             ("{\"heos\": {\"command\": \"event/player_state_changed\", \"message\": \"pid=-1320513458&state=pause\"}}\r\n")
             */
            let parts = self.parseMessageParts(base.heos.message)
            guard let p = parts["pid"], Int(p) == self.pid, let state = parts["state"], let playState = PlayState.init(rawValue: state) else {
                assert(false)
                return true
            }
            DispatchQueue.main.async {
                self.playState = playState
                self.dc.hvc?.updatePlayPauseButton(playState: playState) // so stop=pause
            }
            
        case "event/player_now_playing_changed":
            self.getNowPlayingMedia(stream: stream)

        default:
            DLog("DenonHEOSHandler: \(base.heos.command) is not yet handled")
        }

        // always return true - we received the complete struct
        return true
    }
    
    private func parseMessageParts(_ message: String) -> [String:String] {
        // break pid=-1320513458&state=pause into [pid:-1320513458, state:pause]
        let tuples = message.split(separator: "&")
        return tuples.reduce([:]) { acc, cur in
            let t = cur.split(separator: "=")
            var acc = acc
            acc[String(t[0])] = String(t[1])
            return acc
        }
    }
}

extension Notification.Name {
    static let nowPlayingChanged = Notification.Name.init(rawValue: "now-playing-changed")
}
