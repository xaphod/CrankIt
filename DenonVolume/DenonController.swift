//
//  DenonController.swift
//  DenonVolume
//
//  Created by Tim Carr on 4/29/20.
//  Copyright © 2020 Solodigitalis. All rights reserved.
//

import UIKit
import Network
import MediaPlayer

typealias CommandStringResponseBlock = ((String?, CommandError?)->Void)?
typealias CommandDoubleResponseBlock = ((Double?, CommandError?)->Void)?
typealias CommandNoResponseBlock = ((CommandError?)->Void)?
typealias CommandBoolResponseBlock = ((Bool?, CommandError?)->Void)?

enum CommandError : Error {
    case noDenon
    case noStream
    case noDataReturned
    case dataReturnedNotUnderstood
    case invalidInput
    case cannotChangeVolumeWhileMuted
    case tryAgain
    case streamError(Error)
}

protocol DenonSetting {
    init?(str: String)
    var displayLong: String { get }
    var displayShort: String { get }
    var code: String { get }
    func setValue(denon: DenonController?, _ completionBlock: CommandNoResponseBlock)
}

class DenonController {
    #if DEBUG
    let verbose = true
    #else
    let verbose = false
    #endif
    
    weak var hvc: HomeViewController?
    
    var maxAllowedSafeVolume: Double {
        get { UserDefaults.standard.value(forKey: "dc.maximumVolume") as? Double ?? 80.0 }
        set { UserDefaults.standard.set(newValue, forKey: "dc.maximumVolume") }
    }

    // min instead of 0. Reduce the range by this much to make it more sensitive
    var minimumVolume: Double {
        get { UserDefaults.standard.value(forKey: "dc.minimumVolume") as? Double ?? 30.0 }
        set { UserDefaults.standard.set(newValue, forKey: "dc.minimumVolume")}
    }

    var lastEQ: MultiEQSetting?
    var lastPower: Bool? {
        didSet {
            DLog("main zone power -> \(String(describing: lastPower))")
            
            // first run
            if self.lastPower == true, !UserDefaults.standard.bool(forKey: "hvc.firstRun200") {
                UserDefaults.standard.set(true, forKey: "hvc.firstRun200")
                self.hvc?.showTips()
            }
        }
    }
    var lastVolume: Double?
    var lastVolumeBetween0and1: Double? {
        guard let lastVolume = self.lastVolume else { return nil }
        guard lastVolume <= self.volumeMax, self.volumeMax > 0 else {
            assert(false)
            return nil
        }
        return (lastVolume - minimumVolume) / (maxAllowedSafeVolume - minimumVolume)
    }
    var lastMute: Bool?
    var lastSource: InputSourceSetting? {
        didSet {
            let str = self.receiver.device.friendlyName ?? self.receiver.device.manufacturer
            AudioController.shared.title = "\(str) - \(self.lastSource?.displayLong ?? "")"
            self.hvc?.updateSource(source: self.lastSource, isZone2: false)
        }
    }
    var lastSurroundMode: String?
    var volumeMax = 98.0 {
        didSet {
            if self.verbose == true { DLog("Setting volumeMax to \(self.volumeMax)") }
            self.hvc?.updateVolume(self.lastVolume, isZone2: false)
            self.hvc?.updateVolume(self.zone2Volume, isZone2: true)
        }
    }
    var streams: DenonStreams?
    let host: String
    let receiver: Receiver
    var demoMode = false
    var canReconnect = true
    private let queue = DispatchQueue.init(label: "com.solodigitalis.denonVolume")
    
    var zone2Power: Bool? {
        didSet {
            DLog("zone2Power -> \(String(describing: zone2Power))")
        }
    }
    var zone2Volume: Double?
    var zone2Source: InputSourceSetting? {
        didSet {
            self.hvc?.updateSource(source: self.zone2Source, isZone2: true)
        }
    }
    var zone2Mute: Bool?
    var lastBecameActive = Date.init()

    init(receiver: Receiver) {
        DLog("DC INIT: ipAddress = \(receiver.ipAddress!)")
        self.host = receiver.ipAddress!
        self.receiver = receiver
    }
    
    init(demoMode: Bool) {
        self.host = ""
        self.demoMode = true
        self.receiver = Receiver.init(ipAddress: "0.0.0.0", device: Receiver.Device.init(friendlyName: "Demo mode", manufacturer: "Demo", modelDescription: nil, modelName: nil, modelNumber: nil))
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        DLog("DC DEINIT")
    }
    
    struct InitialState {
        var poweredOn: Bool
        var isMuted: Bool?
        var volume: Double?
        var source: InputSourceSetting?
    }
    
    typealias ConnectCompletionBlock = ((InitialState?)->Void)?
    private var connectCompletionBlock: ConnectCompletionBlock = nil
    
    func connect(_ completionBlock: ConnectCompletionBlock = nil) {
        DLog("DenonController: connect()")
        guard !self.demoMode else {
            completionBlock?(self.demoModeInitialState())
            return
        }

        self.streams?.disconnect()
        self.connectCompletionBlock = completionBlock
        self.streams = DenonStreams.init(host: self.host, port: 23, queue: self.queue, dc: self)
    }
    
    func connectionStateChanged(state: NWConnection.State) {
        switch state {
        case .cancelled, .failed(_):
            self.streams?.dc = nil
            self.streams = nil
            self.hvc?.connectionStateChanged(isConnected: false)
            if self.canReconnect {
                DispatchQueue.main.asyncAfter(deadline: .now() + CONNECTION_DELAY) { [weak self] in
                    self?.connect()
                }
            }

        case .waiting(_):
            self.hvc?.connectionStateChanged(isConnected: false)

        case.ready:
            let completionBlock = self.connectCompletionBlock
            self.connectCompletionBlock = nil
            self.readPowerAndZ2State() { (power, _) in
                guard let power = power else {
                    completionBlock?(nil)
                    return
                }
                guard power else {
                    self.hvc?.connectionStateChanged(isConnected: true)
                    completionBlock?(InitialState.init(poweredOn: false, isMuted: nil, volume: nil))
                    return
                }
                self.getInitialState(powerState: power, completionBlock)
            }

        default: break
        }
    }
    
    private func demoModeInitialState() -> InitialState {
        self.lastSource = .init(input: .dvd, isZone2: false)
        self.lastMute = false
        self.lastEQ = .init(eq: .audyssey)
        self.lastPower = true
        self.lastVolume = 50
        self.lastSurroundMode = "STEREO"
        self.hvc?.connectionStateChanged(isConnected: true)
        self.hvc?.updateSurroundMode()
        return InitialState.init(poweredOn: true, isMuted: false, volume: 50, source: self.lastSource)
    }
    
    fileprivate func getInitialState(powerState: Bool, attempt: Int = 1, _ completionBlock: ConnectCompletionBlock) {
        guard !self.demoMode else {
            completionBlock?(self.demoModeInitialState())
            return
        }

        if self.verbose {
            DLog("getInitialState() - readVolume, readMuteState, readSourceState")
        }
        self.readVolume() { (_) in
            self.readMuteState { (_) in
                self.readSourceState { (_) in
                    if let vol = self.lastVolume, let muted = self.lastMute, let source = self.lastSource {
                        self.hvc?.connectionStateChanged(isConnected: true)
                        completionBlock?(InitialState.init(poweredOn: powerState, isMuted: muted, volume: vol, source: source))
                        
                        // after completionBlock, cuz we don't wanna wait for it
                        self.issueCommand("MS?", minLength: 3, responseLineRegex: "MS.+", timeoutBlock: {
                            self.readMultiEQState()
                        }) { (_, _) in
                            self.readMultiEQState()
                        }
                        return
                    }
                    if self.streams?.connection.state == .ready, attempt <= 3 {
                        DLog("DC getInitialState: failed, connection.state=ready, will retry...")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                            self?.getInitialState(powerState: powerState, attempt: attempt+1, completionBlock)
                        }
                        return
                    }
                    DLog("DC getInitialState: failing out after \(attempt) attempts")
                    completionBlock?(nil)
                }
            }
        }
    }
    
    func disconnect() {
        DLog("DC disconnect()")
        guard !self.demoMode, let streams = self.streams else {
            return
        }
        streams.disconnect()
        self.streams = nil
    }

    func readMultiEQState(_ completionBlock: CommandNoResponseBlock = nil) {
        guard !self.demoMode else {
            completionBlock?(nil)
            return
        }

        self.issueCommand("PSMULTEQ: ?", minLength: 10, responseLineRegex: "PSMULTEQ:.+", timeoutBlock: {
            completionBlock?(.tryAgain)
        }) { (str, err) in
            guard let _ = str else {
                completionBlock?(err ?? CommandError.noDataReturned)
                return
            }
            completionBlock?(nil)
        }
    }
    
    func readSourceState(_ completionBlock: CommandNoResponseBlock = nil) {
        guard !self.demoMode else {
            completionBlock?(nil)
            return
        }

        self.issueCommand("SI?", minLength: 4, responseLineRegex: "SI.+", timeoutBlock: {
            completionBlock?(.tryAgain)
        }) { (str, err) in
            guard let _ = str else {
                completionBlock?(err ?? CommandError.noDataReturned)
                return
            }
            completionBlock?(nil)
        }
    }

    func readPowerAndZ2State(_ completionBlock: CommandBoolResponseBlock = nil) {
        guard !self.demoMode else {
            completionBlock?(true, nil)
            return
        }

        self.issueCommand("ZM?", minLength: 4, responseLineRegex: #"(ZMON)|(ZMOFF)|(PWSTANDBY)"#, timeoutBlock: {
            completionBlock?(self.lastPower, nil)
        }) { (pwstr, err) in
            guard let pwstr = pwstr else {
                completionBlock?(nil, err ?? CommandError.noDataReturned)
                return
            }
            
            let work = {
                if pwstr.hasPrefix("ZMON") {
                    self.lastPower = true
                    completionBlock?(true, nil)
                } else if pwstr.hasPrefix("ZMOFF") || pwstr.hasPrefix("PWSTANDBY") {
                    self.lastPower = false
                    completionBlock?(false, nil)
                } else {
                    completionBlock?(nil, .dataReturnedNotUnderstood)
                }
            }
            
            // these are processed as events in parseResponseHelper() below
            // PW? actually does yield Z2ON when zone 2 is on, but, Z2? gets the rest of the zone2 info; example response:
            /*
             Z2ON
             Z2NET
             Z201
             SVON
             */
            // Note: Z201 means "zone 2 volume is currently set to 01"
            self.issueCommand("Z2?", minLength: 4, responseLineRegex: nil, timeoutBlock: {
                work()
            }) { (_, _) in
                work()
            }
        }
    }
    
    func setPowerToStandby() {
        self.issueCommand("PWSTANDBY", minLength: 4, responseLineRegex: #"PWSTANDBY.*"#, timeoutBlock: {
        }) { (_, _) in
        }
    }
    
    func togglePowerState(isZone2: Bool, _ completionBlock: ConnectCompletionBlock = nil) {
        guard !self.demoMode else {
            self.lastPower = !(self.lastPower!)
            completionBlock?(nil)
            return
        }

        guard let z1PowerState = self.lastPower, let z2PowerState = self.zone2Power else {
            self.readPowerAndZ2State()
            completionBlock?(nil)
            return
        }
        let powerState = isZone2 ? z2PowerState : z1PowerState

        // Turning OFF
        if powerState {
            self.issueCommand(isZone2 ? "Z2OFF" : "ZMOFF", minLength: 4, responseLineRegex: isZone2 ? #"Z2OFF.*"# :  #"ZMOFF.*"#, timeoutBlock: {
                completionBlock?(nil)
            }) { (str, error) in
                DispatchQueue.main.asyncAfter(deadline: .now() + CONNECTION_DELAY) { [weak self] in
                    guard let self = self else { return }
                    if isZone2 {
                        self.zone2Power = !powerState
                    } else {
                        self.lastPower = !powerState
                    }
                    completionBlock?(InitialState.init(poweredOn: !powerState, isMuted: nil, volume: nil))
                }
            }
            return
        }

        // Turning ON
        self.issueCommand(isZone2 ? "Z2ON" : "ZMON", minLength: 4, responseLineRegex: isZone2 ? #"Z2ON.*"# : #"ZMON.*"#, timeoutTime: 3.9, timeoutBlock: {
            completionBlock?(nil)
        }) { (str, error) in
            guard let _ = str else {
                completionBlock?(nil)
                return
            }
            if isZone2 {
                self.zone2Power = !powerState
            } else {
                self.lastPower = !powerState
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
                self?.getInitialState(powerState: !powerState, completionBlock)
            }
        }
    }

    func readMuteState(_ completionBlock: CommandNoResponseBlock = nil) {
        guard !self.demoMode else {
            completionBlock?(nil)
            return
        }

        self.issueCommand("MU?", minLength: 4, responseLineRegex: #"(MUON)|(MUOFF)"#, timeoutBlock: {
            completionBlock?(.tryAgain)
        }) { (str, err) in
            guard let _ = str else {
                completionBlock?(err ?? CommandError.noDataReturned)
                return
            }
            
            self.issueCommand("Z2MU?", minLength: 4, responseLineRegex: nil, timeoutBlock: {
                completionBlock?(nil)
            }) { _, _ in
                // response is handled in parseResponseHelper() below
                completionBlock?(nil)
            }
        }
    }
    
    func toggleMuteState(isZone2: Bool, _ completionBlock: CommandNoResponseBlock = nil) {
        guard !self.demoMode else {
            self.lastMute = !(self.lastMute!)
            completionBlock?(nil)
            return
        }

        let muteBool = isZone2 ? self.zone2Mute : self.lastMute
        guard let muteState = muteBool else {
            self.readMuteState()
            completionBlock?(.tryAgain)
            return
        }
        var cmd = muteState ? "MUOFF" : "MUON"
        if isZone2 {
            cmd = "Z2\(cmd)"
        }
        self.issueCommand(cmd, minLength: 4, responseLineRegex: "\(cmd).*", timeoutBlock: {
            completionBlock?(nil)
        }) { (str, error) in
            guard let _ = str else {
                completionBlock?(error ?? CommandError.noDataReturned)
                return
            }
            if isZone2 {
                self.zone2Mute = !muteState
            } else {
                self.lastMute = !muteState
            }
            completionBlock?(nil)
        }
    }
    
    // VOLUME: "80" is 0dB
    func readVolume(_ completionBlock: CommandNoResponseBlock = nil) {
        guard !self.demoMode else {
            completionBlock?(nil)
            return
        }
        
        self.issueCommand("MV?", minLength: 4, responseLineRegex: #"MV(?!MAX).*"#, timeoutBlock: {
            completionBlock?(.tryAgain)
        }) { (str, err) in
            guard let _ = str else {
                completionBlock?(err ?? CommandError.noDataReturned)
                return
            }
            completionBlock?(nil)
        }
    }
    
    func setVolume(volumeBetween0and1: Float, isZone2: Bool, _ completionBlock: CommandDoubleResponseBlock = nil) {
        // translate 0...1 to minimumVolume...maxAllowedSafeVolume
        let volume = (Double(volumeBetween0and1) * (maxAllowedSafeVolume - minimumVolume)) + minimumVolume
        self.setVolume(volume, isZone2: isZone2, completionBlock)
    }
    
    // Expects whole values from 0...volumeMax only!
    func setVolume(_ volumeDouble: Double, isZone2: Bool, _ completionBlock: CommandDoubleResponseBlock = nil) {
        guard (0...98).contains(volumeDouble) else {
            completionBlock?(nil, .invalidInput)
            return
        }
        
        guard !self.demoMode else {
            self.lastVolume = volumeDouble
            completionBlock?(volumeDouble, nil)
            return
        }
        
        let muteBool = isZone2 ? self.zone2Mute : self.lastMute
        if muteBool == true {
            self.readMuteState()
            completionBlock?(nil, .cannotChangeVolumeWhileMuted)
            return
        }

        let volumeBool = isZone2 ? self.zone2Volume : self.lastVolume
        if let lastVolume = volumeBool, lastVolume == volumeDouble {
            DLog("DC setVolume(\(volumeDouble)) - no change, doing a read instead")
            self.readVolume() { (err) in
                completionBlock?(isZone2 ? self.zone2Volume : self.lastVolume, err)
            }
            return
        }
        
        let val: String
        if isZone2 || floor(volumeDouble) == volumeDouble {
            val = String(format: "%02d", Int(volumeDouble))
        } else {
            // we assume val is xx.5
            val = String(format: "%02d5", Int(volumeDouble))
        }

        self.issueCommand("\(isZone2 ? "Z2" : "MV")\(val)", canQueue: false, minLength: 2, responseLineRegex: isZone2 ? #"Z2(?!ON)[0-9]{2,3}.*"# : #"MV(?!MAX).*"#, timeoutBlock: {
            completionBlock?(nil, .tryAgain) // don't report old values here since changing so fast
        }) { (str, err) in
            DLog("DC setVolume(\(volumeDouble)): (\(val)) -> \(str ?? "nil") for zone \(isZone2 ? "2" : "1")")

            guard let str = str else {
                completionBlock?(nil, err ?? CommandError.noDataReturned)
                return
            }
            guard let dbl = self.volumeFromString(str) else {
                completionBlock?(nil, err ?? CommandError.dataReturnedNotUnderstood)
                return
            }
            if isZone2 {
                self.zone2Volume = dbl
            } else {
                self.lastVolume = dbl
            }
            completionBlock?(dbl, nil)
        }
    }
    
    func issueCommand(_ command: String, canQueue: Bool = true, minLength: Int, responseLineRegex: String?, timeoutTime: TimeInterval = DenonStreams.TIMEOUT_TIME, timeoutBlock: @escaping ()->Void, _ completionBlock: CommandStringResponseBlock) {
        guard !self.demoMode else {
            completionBlock?(responseLineRegex, nil)
            return
        }

        guard let streams = self.streams else {
            completionBlock?(nil, .noStream)
            return
        }
        
        if self.verbose { DLog("DC \(command.filter({ !$0.isWhitespace }))") }
        
        let tBlock = {
            DLog("DC issueCommand: \(command) TIMED OUT")
            timeoutBlock()
        }

        streams.writeAndRead((command+"\r").data(using: .ascii)!, canQueue: canQueue, timeoutTime: timeoutTime, timeoutBlock: tBlock, minLength: minLength, responseLineRegex: responseLineRegex) { (str, error) in
            if let error = error {
                DLog("DC issueCommand: ERROR writing, disconnecting - \(error)")
                self.disconnect()
                completionBlock?(nil, .streamError(error))
                return
            }

            if let str = str {
                if self.verbose { DLog("DC \(command.filter({ !$0.isWhitespace })) -> \(str.replacingOccurrences(of: "\r", with: "/"))") }
                completionBlock?(str, nil)
                return
            }
            DLog("DC issueCommand: ERROR on readLine, disconnecting")
            self.disconnect()
            completionBlock?(nil, .noDataReturned)
        }
    }

    func volumeFromString(_ str: String) -> Double? {
        guard (str.hasPrefix("MV") || str.hasPrefix("Z2")), str.count >= 4 else {
            DLog("DC volumeFromString: warning, \(str) not MV/Z2xxx - not a volume")
            return nil
        }
        // Range: 00, 005 .... 10, 105, ... 98 (max)
        
        let regex = try? NSRegularExpression(pattern: #"(?:Z2|MV)(?:MAX){0,1} ?([0-9]{2,3}).*"#, options: [])
        let nsrange = NSRange(str.startIndex..<str.endIndex, in: str)
        var dbl: Double?
        regex?.enumerateMatches(in: str, options: [], range: nsrange) { (match, _, stop) in
            guard let match = match else { return }

            // the whole string itself is the first match range
            if match.numberOfRanges == 2, let firstCaptureRange = Range(match.range(at: 1), in: str) {
                let matchStr = String(str[firstCaptureRange])
                
                dbl = matchStr.count == 3 ? (Double(matchStr)! / 10.0) : Double(matchStr)
                stop.pointee = true
            }
        }
        if self.verbose { DLog("DC volumeFromString: \(str) -> \(dbl ?? -999)") }
        
        return dbl
    }
    
    // handle side-effects of parsing output that wasn't asked for
    // NOT ON MAIN THREAD
    func parseResponseHelper(line: String.SubSequence) -> Bool {
        // new: handle power state changes
        if line.hasPrefix("PWSTANDBY") {
            DispatchQueue.main.async {
                self.lastPower = false
                self.zone2Power = false
                self.hvc?.powerStateDidUpdate()
            }
            return true
        }
        if line.hasPrefix("PWON") {
            DispatchQueue.main.async {
                self.lastPower = true
                self.hvc?.powerStateDidUpdate()
            }
            return true
        }
        
        if line.hasPrefix("Z2") {
            // Zone 2 things we handle here:
            // Z2ON, Z2OFF (power)
            // Z2NET (source)
            // Z201 (volume)
            // Z2MUON, Z2MUOFF (mute)
            
            if line.hasPrefix("Z2ON") {
                DispatchQueue.main.async {
                    self.zone2Power = true
                    self.hvc?.powerStateDidUpdate()
                }
                return true
            }
            if line.hasPrefix("Z2OFF") {
                DispatchQueue.main.async {
                    self.zone2Power = false
                    self.hvc?.powerStateDidUpdate()
                }
                return true
            }

            if let newSource = InputSourceSetting.init(str: String(line)) {
                DispatchQueue.main.async {
                    self.zone2Source = newSource // has didSet
                }
                return true
            }

            // Note: Z2MU? returns "PVOFF" and then "Z2MUOFF" on my AVR-3600 when zone 2 is powered off
            if line.hasPrefix("Z2MUON") || line.hasPrefix("Z2MUOFF") {
                DispatchQueue.main.async {
                    if line.hasPrefix("Z2MUON") {
                        self.zone2Mute = true
                    } else if line.hasPrefix("Z2MUOFF") {
                        self.zone2Mute = false
                    } else {
                        assert(false)
                    }
                    self.hvc?.updateMuteState(muteState: self.zone2Mute, isZone2: true)
                }
                return true
            }

            // Z2 volume is expected to be in format Z201...Z298
            if let vol = self.volumeFromString(String(line)) {
                DispatchQueue.main.async {
                    self.zone2Volume = vol
                    self.hvc?.updateVolume(vol, isZone2: true)
                }
                return true
            }
            
            // unhandled Z2 command
            return false
        }
        if line.hasPrefix("MVMAX") {
            DispatchQueue.main.async {
                let maxVol = self.volumeFromString(String(line))
                if let maxVol = maxVol {
                    self.volumeMax = maxVol
                }
            }
            return true
        }
        if line.hasPrefix("SI") {
            DispatchQueue.main.async {
                if let newSource = InputSourceSetting.init(str: String(line)) {
                    self.lastSource = newSource
                } else {
                    var source = InputSourceSetting.init(input: .unknown, isZone2: false)
                    let index = line.index(line.startIndex, offsetBy: 2)
                    source.code = String(line)
                    source.displayLong = String(line.suffix(from: index))
                    source.displayShort = String(line.suffix(from: index).prefix(4))
                    self.lastSource = source // has didSet
                    DLog("DC readSourceState: unknown source \(line)")
                }
            }
            return true
        }
        if line.hasPrefix("MS") {
            DispatchQueue.main.async {
                let index = line.index(line.startIndex, offsetBy: 2)
                let surround = String(line.suffix(from: index))
                if surround.count > 0 {
                    self.lastSurroundMode = surround
                    self.hvc?.updateSurroundMode()
                }
            }
            return true
        }
        if line.hasPrefix("MV") && !line.hasPrefix("MVMAX") {
            DispatchQueue.main.async {
                let vol = self.volumeFromString(String(line))
                self.lastVolume = vol
                self.hvc?.updateVolume(vol, isZone2: false)
            }
            return true
        }
        if line.hasPrefix("MU") {
            DispatchQueue.main.async {
                let str = String(line)
                if str.hasPrefix("MUON") {
                    self.lastMute = true
                } else if str.hasPrefix("MUOFF") {
                    self.lastMute = false
                } else {
                    assert(false)
                }
                self.hvc?.updateMuteState(muteState: self.lastMute, isZone2: false)
            }
            return true
        }
        if line.hasPrefix("PSMULTEQ:"), let eq = MultiEQSetting.init(str: String(line)) {
            DispatchQueue.main.async {
                self.lastEQ = eq
                self.hvc?.updateSurroundMode()
            }
            return true
        }
        
        return false
    }
}
