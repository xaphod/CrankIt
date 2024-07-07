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
    let verbose = false
    
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
    var lastPower: Bool?
    var lastVolume: Double?
    var lastVolumeBetween0and1: Double? {
        guard let lastVolume = self.lastVolume else { return nil }
        guard lastVolume <= self.volumeMax, self.volumeMax > 0 else {
            assert(false)
            return nil
        }
        return (lastVolume - minimumVolume) / ((maxAllowedSafeVolume ?? volumeMax) - minimumVolume)
    }
    var lastMute: Bool?
    var lastSource: InputSourceSetting? {
        didSet {
            let str = self.receiver.device.friendlyName ?? self.receiver.device.manufacturer
            AudioController.shared.title = "\(str) - \(self.lastSource?.displayLong ?? "")"
            self.hvc?.updateSource(source: self.lastSource)
        }
    }
    var lastSurroundMode: String?
    var volumeMax = 98.0 {
        didSet {
            if self.verbose == true { DLog("Setting volumeMax to \(self.volumeMax)") }
            self.hvc?.updateVolume(self.lastVolume)
        }
    }
    var streams: DenonStreams?
    let host: String
    let receiver: Receiver
    var demoMode = false
    var canReconnect = true
    private let queue = DispatchQueue.init(label: "com.solodigitalis.denonVolume")
    
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
            self.readPowerState() { (power, _) in
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
        self.lastSource = .init(input: .dvd)
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
    
    @objc func volumeUp() {
        DLog("DC volumeUp()")
        guard
            let muteState = self.lastMute,
            !muteState,
            let powerState = self.lastPower,
            powerState
        else { return }
        
        self.readVolume { (_) in
            guard let volume = self.lastVolume else { return }
            self.setVolume(min(self.volumeMax, volume+2.0)) { (vol, err) in
                self.hvc?.updateVolume(vol)
            }
        }
    }
    
    @objc func volumeDown() {
        DLog("DC volumeDown()")
        guard
            let muteState = self.lastMute,
            !muteState,
            let powerState = self.lastPower,
            powerState
        else { return }

        self.readVolume { (_) in
            guard let volume = self.lastVolume else { return }
             self.setVolume(max(0, volume-2.0)) { (vol, err) in
                self.hvc?.updateVolume(vol)
            }
        }
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
    
    func setSource(_ source: String, completionBlock: CommandBoolResponseBlock = nil) {
        guard !self.demoMode else {
            completionBlock?(true, nil)
            return
        }

        var sourceMod = source
        if source == "MPLAY" {
            sourceMod = "SMPLAY"
        }
        self.issueCommand("SI\(sourceMod)", minLength: 2+source.count, responseLineRegex: "SI\(source).*", timeoutBlock: {
            completionBlock?(nil, CommandError.tryAgain)
        }) { (str, err) in
            guard let str = str else {
                completionBlock?(nil, err ?? CommandError.noDataReturned)
                return
            }
            completionBlock?(str.hasPrefix("SI\(source)"), nil)
        }
    }
    
    func readPowerState(_ completionBlock: CommandBoolResponseBlock = nil) {
        guard !self.demoMode else {
            completionBlock?(true, nil)
            return
        }

        self.issueCommand("PW?", minLength: 4, responseLineRegex: #"(PWON)|(PWSTANDBY)"#, timeoutBlock: {
            completionBlock?(self.lastPower, nil)
        }) { (str, err) in
            guard let str = str else {
                completionBlock?(nil, err ?? CommandError.noDataReturned)
                return
            }
            if str.hasPrefix("PWON") {
                self.lastPower = true
                completionBlock?(true, nil)
            } else if str.hasPrefix("PWSTANDBY") {
                self.lastPower = false
                completionBlock?(false, nil)
            } else {
                completionBlock?(nil, .dataReturnedNotUnderstood)
            }
        }
    }
    
    func togglePowerState(_ completionBlock: ConnectCompletionBlock = nil) {
        guard !self.demoMode else {
            self.lastPower = !(self.lastPower!)
            completionBlock?(nil)
            return
        }

        guard let powerState = self.lastPower else {
            self.readPowerState()
            completionBlock?(nil)
            return
        }
        if powerState {
            let work = {
                self.issueCommand("PWSTANDBY", minLength: 4, responseLineRegex: "PWSTANDBY.*", timeoutBlock: {
                    completionBlock?(nil)
                }) { (str, error) in
                    DispatchQueue.main.asyncAfter(deadline: .now() + CONNECTION_DELAY) { [weak self] in
                        guard let self = self else { return }
                        self.lastPower = !powerState
                        completionBlock?(InitialState.init(poweredOn: !powerState, isMuted: nil, volume: nil))
                    }
                }
            }

            self.issueCommand("Z2?", minLength: 4, responseLineRegex: #"(Z2ON)||(Z2OFF)"#, timeoutBlock: {
                work()
            }) { (str, _) in
                if let str = str, str.hasPrefix("Z2ON") {
                    self.issueCommand("Z2OFF", minLength: 4, responseLineRegex: nil, timeoutBlock: {
                        work()
                    }) { (_, _) in
                        work()
                    }
                    return
                }
                work()
            }
            return
        }
        self.issueCommand("PWON", minLength: 4, responseLineRegex: "PWON.*", timeoutBlock: {
            completionBlock?(nil)
        }) { (str, error) in
            guard let _ = str else {
                completionBlock?(nil)
                return
            }
            self.lastPower = !powerState
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
            completionBlock?(nil)
        }
    }
    
    func toggleMuteState(_ completionBlock: CommandNoResponseBlock = nil) {
        guard !self.demoMode else {
            self.lastMute = !(self.lastMute!)
            completionBlock?(nil)
            return
        }

        guard let muteState = self.lastMute else {
            self.readMuteState()
            completionBlock?(.tryAgain)
            return
        }
        let cmd = muteState ? "MUOFF" : "MUON"
        self.issueCommand(cmd, minLength: 4, responseLineRegex: "\(cmd).*", timeoutBlock: {
            completionBlock?(nil)
        }) { (str, error) in
            guard let _ = str else {
                completionBlock?(error ?? CommandError.noDataReturned)
                return
            }
            self.lastMute = !muteState
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
    
    func setVolume(volumeBetween0and1: Float, _ completionBlock: CommandDoubleResponseBlock = nil) {
        // translate 0...1 to minimumVolume...maxAllowedSafeVolume
        let volume = (Double(volumeBetween0and1) * (maxAllowedSafeVolume - minimumVolume)) + minimumVolume
        self.setVolume(volume, completionBlock)
    }
    
    // Expects whole values from 0...volumeMax only!
    func setVolume(_ volumeDouble: Double, _ completionBlock: CommandDoubleResponseBlock = nil) {
        guard (0...98).contains(volumeDouble) else {
            completionBlock?(nil, .invalidInput)
            return
        }
        
        guard !self.demoMode else {
            self.lastVolume = volumeDouble
            completionBlock?(volumeDouble, nil)
            return
        }
        
        if self.lastMute == true {
            self.readMuteState()
            completionBlock?(nil, .cannotChangeVolumeWhileMuted)
            return
        }

        if let lastVolume = self.lastVolume, lastVolume == volumeDouble {
            DLog("DC setVolume(\(volumeDouble)) - is lastVolume, doing a read instead")
            self.readVolume() { (err) in
                completionBlock?(self.lastVolume, err)
            }
            return
        }
        
        let val: String
        if floor(volumeDouble) == volumeDouble {
            val = String(format: "%02d", Int(volumeDouble))
        } else {
            // we assume val is xx.5
            val = String(format: "%02d5", Int(volumeDouble))
        }

        self.issueCommand("MV\(val)", minLength: 2, responseLineRegex: #"MV(?!MAX).*"#, timeoutBlock: {
            completionBlock?(nil, .tryAgain) // don't report old values here since changing so fast
        }) { (str, err) in
            DLog("DC setVolume(\(volumeDouble)): (\(val)) -> \(str ?? "nil")")

            guard let str = str else {
                completionBlock?(nil, err ?? CommandError.noDataReturned)
                return
            }
            guard let dbl = self.volumeFromString(str) else {
                completionBlock?(nil, err ?? CommandError.dataReturnedNotUnderstood)
                return
            }
            self.lastVolume = dbl
            completionBlock?(dbl, nil)
        }
    }
    
    func issueCommand(_ command: String, minLength: Int, responseLineRegex: String?, timeoutBlock: @escaping ()->Void, _ completionBlock: CommandStringResponseBlock) {
        guard !self.demoMode else {
            completionBlock?(responseLineRegex, nil)
            return
        }

        guard let streams = self.streams else {
            completionBlock?(nil, .noStream)
            return
        }
        
        if self.verbose { DLog("DC \(command.filter({ !$0.isWhitespace }))") }
        streams.write((command+"\r").data(using: .ascii)!, timeoutBlock: timeoutBlock) { (error) in
            if let error = error {
                DLog("DC issueCommand: ERROR writing, disconnecting - \(error)")
                self.disconnect()
                completionBlock?(nil, .streamError(error))
                return
            }
            streams.readLine(minLength: minLength, responseLineRegex: responseLineRegex, timeoutBlock: timeoutBlock) { (str) in
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
    }

    func volumeFromString(_ str: String) -> Double? {
        guard str.hasPrefix("MV"), str.count >= 4 else {
            DLog("DC volumeFromString: warning, \(str) not MVxxx - not a volume")
            return nil
        }
        // Range: 00, 005 .... 10, 105, ... 98 (max)

        let regex = try? NSRegularExpression(pattern: #"MV(?:MAX){0,1} ?([0-9]{2,3}).*"#, options: [])
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
        if self.verbose { DLog("DC volumeFromString: \(str) -> \(dbl ?? -1)") }
        return dbl
    }
    
    // handle side-effects of parsing output that wasn't asked for
    // NOT ON MAIN THREAD
    func parseResponseHelper(line: String.SubSequence) -> Bool {
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
                    var source = InputSourceSetting.init(input: .unknown)
                    let index = line.index(line.startIndex, offsetBy: 2)
                    source.code = String(line)
                    source.displayLong = String(line.suffix(from: index))
                    source.displayShort = String(line.suffix(from: index).prefix(4))
                    self.lastSource = source
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
                self.hvc?.updateVolume(vol)
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
                self.hvc?.updateMuteState(muteState: self.lastMute)
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
