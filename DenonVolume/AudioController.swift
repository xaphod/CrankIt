//
//  AudioController.swift
//  DenonVolume
//
//  Created by Tim Carr on 5/4/20.
//  Copyright © 2020 Solodigitalis. All rights reserved.
//

import Foundation
import MediaPlayer
import AVFoundation

class AudioController {
    static let shared = AudioController.init()
    var filename: String?
    var title: String = "" { // set by DenonController
        didSet {
            self.setupPlayer()
        }
    }
    
    var disabled: Bool {
        get { UserDefaults.standard.bool(forKey: "audioController.disabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "audioController.disabled")
            if !newValue {
                self.setupPlayer()
            } else {
                self.stopPlayer()
            }
        }
    }

    fileprivate let delegate = AudioControllerDelegate.init()
    fileprivate var obs: NSKeyValueObservation?
    fileprivate var player: AVAudioPlayer?
    fileprivate var volumeSetInProgress = false
    fileprivate var volumeSetQueueOfOne: Float?
    fileprivate var playTarget: Any?
    fileprivate var pauseTarget: Any?
    fileprivate var lastActiveState = Date.init()
    fileprivate var lastVolumeButtonPress = Date.init()

    private var ignoredFirstObserverOld = false

    init() {
        delegate.ac = self
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .default)
        try? audioSession.setActive(true, options: [])
        
        self.obs = audioSession.observe(\.outputVolume, options: [.old]) { (av, change) in
            guard self.volumeSetInProgress == false else {
                DLog("AudioController volumeSetInProgress, queueing...")
                self.volumeSetQueueOfOne = av.outputVolume
                return
            }
            guard let denon = AppDelegate.shared.denon else {
                return
            }
            self.lastVolumeButtonPress = Date.init()

            if let lastVolume = denon.lastVolumeBetween0and1, abs(lastVolume - Double(av.outputVolume)) > 0.15 {
                var nextVal = Float(lastVolume)
                if self.ignoredFirstObserverOld {
                    if let oldVal = change.oldValue {
                        nextVal += (av.outputVolume - oldVal)
                    }
                } else {
                    self.ignoredFirstObserverOld = true
                }
                DLog("AudioController: vol difference too big; lastVolume=\(lastVolume) oldVal=\(change.oldValue!), av.outputVolume=\(av.outputVolume), nextVal=\(nextVal)")
                self.volumeSetQueueOfOne = nil
                MPVolumeView.setVolume(nextVal) // this will cause us to be called again
                return
            }
            DLog("AudioController: setting vol=\(av.outputVolume)")

            self.volumeSetInProgress = true
            AppDelegate.shared.denon?.setVolume(volumeBetween0and1: av.outputVolume) { (v, _) in
                assert(Thread.current.isMainThread)

                if let v = v {
                    NotificationCenter.default.post(name: .volumeChangedByButton, object: nil, userInfo: ["volume":v])
                }
                guard let queued = self.volumeSetQueueOfOne else {
                    self.volumeSetInProgress = false
                    return
                }
                self.volumeSetQueueOfOne = nil
                
                denon.setVolume(volumeBetween0and1: queued) { (v, _) in
                    if let v = v {
                        NotificationCenter.default.post(name: .volumeChangedByButton, object: nil, userInfo: ["volume":v])
                    }
                    self.volumeSetInProgress = false
                }
                return
            }
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleInterruption), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.didBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func didBecomeActive() {
        self.lastActiveState = Date.init()
        self.setupPlayer()
    }

    @objc func setupPlayer() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try? audioSession.setCategory(.playback, mode: .default)
            try? audioSession.setActive(true, options: [])

            if self.disabled {
                DLog("AudioController setupPlayer(): disabled")
                return
            }
            DLog("AudioController setupPlayer(): enabled, starting...")
            let timeTilStopPlaying = TimeInterval(60 * 60)
            if UIApplication.shared.applicationState == .background {
                // if it has been a while in the background + a while since we got a button press, stop
                if abs(self.lastVolumeButtonPress.timeIntervalSinceNow) > timeTilStopPlaying && abs(self.lastActiveState.timeIntervalSinceNow) > timeTilStopPlaying {
                    DLog("AudioController setupPlayer(): too long in background without button press, dropping.")
                    return
                }
            } else {
                self.lastActiveState = Date.init()
            }
            
            let url = Bundle.main.url(forResource: self.filename ?? "silence-1min", withExtension: "mp3")
            self.player?.delegate = nil
            self.player?.stop()
            self.player = try AVAudioPlayer(contentsOf: url!)
            self.player?.delegate = self.delegate
            self.player?.prepareToPlay()
            self.player?.play()
            self.setupNowPlaying()
            self.setupRemoteTransportControls()
        } catch let error as NSError {
            DLog("AudioController: Failed to init audio player - \(error)")
        }
    }
    
    func stopPlayer() {
        DLog("AudioController stopPlayer()")
        self.player?.stop()
        self.player?.currentTime = 0
        let commandCenter = MPRemoteCommandCenter.shared()
        if let playTarget = self.playTarget {
            commandCenter.playCommand.removeTarget(playTarget)
        }
        if let pauseTarget = self.pauseTarget {
            commandCenter.pauseCommand.removeTarget(pauseTarget)
        }
        self.playTarget = nil
        self.pauseTarget = nil
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
    
    func setupNowPlaying() {
        guard let player = self.player else { return }
        var nowPlayingInfo = [String : Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = self.title
        let image = UIImage.init(named: "denon")!
        nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = player.duration
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = player.rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        // Add handler for Play Command
        commandCenter.playCommand.removeTarget(self.playTarget)
        self.playTarget = commandCenter.playCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            guard self.player?.isPlaying == false else {
                return .success
            }
            if self.player?.play() == true {
                return .success
            }
            return .commandFailed
        }

        // Add handler for Pause Command
        commandCenter.pauseCommand.removeTarget(self.pauseTarget)
        self.pauseTarget = commandCenter.pauseCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            guard self.player?.isPlaying == true else {
                return .success
            }
            if self.player?.play() == true {
                return .success
            }
            return .commandFailed
        }
    }
    
    @objc func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
            let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
        }

        if type == .began {
            DLog("AudioController: Interruption began")
            self.player?.pause()
        } else if type == .ended {
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    // Interruption Ended - playback should resume
                    DLog("AudioController: Interruption Ended - playback should resume")
                    self.player?.play()
                } else {
                    // Interruption Ended - playback should NOT resume
                    DLog("AudioController: Interruption Ended - playback should NOT resume")
                }
            }
        }
    }
}

class AudioControllerDelegate : NSObject {
    weak var ac: AudioController?
}

extension AudioControllerDelegate : AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let isInBackground = UIApplication.shared.applicationState == .background
        DLog("AudioController: player did finish playing \(isInBackground ? "in background" : ""), flag=\(flag)")
        if (flag) {
            self.ac?.setupPlayer()
        }
    }
}

extension Notification.Name {
    static let volumeChangedByButton = Notification.Name.init("volumeChangedByButton")
}
