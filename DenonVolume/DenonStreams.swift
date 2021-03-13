//
//  DenonStreams.swift
//  DenonVolume
//
//  Created by Tim Carr on 4/29/20.
//  Copyright © 2020 Solodigitalis. All rights reserved.
//

import Foundation
import Network

class DenonStreams {
    weak var dc: DenonController?
    let connection: NWConnection
    let queue: DispatchQueue
    let lock = NSLock.init()
    private var unprocessedReceived = ""
    private let TIMEOUT_TIME: TimeInterval = 2
    var lastOpMillis: Double = 0
    
    fileprivate var receiveWaiter: ((String?)->Void)?

    init(host: String, port: Int, queue: DispatchQueue, dc: DenonController) {
        self.dc = dc
        let connection = NWConnection.init(host: .init(host), port: .init(integerLiteral: NWEndpoint.Port.IntegerLiteralType(port)), using: .tcp)
        self.connection = connection
        self.queue = queue
        connection.stateUpdateHandler = self.stateUpdateHandler
        connection.start(queue: queue)
    }
    
    func disconnect() {
        DLog("DenonStreams: disconnect()")
        self.connection.cancel()
    }
    
    fileprivate func stateUpdateHandler(state: NWConnection.State) {
        let waiter = self.receiveWaiter
        self.receiveWaiter = nil
        waiter?(nil)

        switch state {
        case .cancelled:
            DLog("stateUpdateHandler: cancelled")
        case .failed(let error):
            DLog("stateUpdateHandler: ERROR - \(error)")
        case .preparing:
            DLog("stateUpdateHandler: preparing")
        case .waiting(let error):
            DLog("stateUpdateHandler: waiting, \(error)")
            switch error {
            case .posix(let posixErrorCode):
                if posixErrorCode == .ECONNREFUSED {
                    DLog("connectionStateChanged: Connection Refused")
                }
            default:
                break
            }

        case .setup:
            DLog("stateUpdateHandler: setup")
        case .ready:
            DLog("stateUpdateHandler: ready")
            self.receiveLoop()
        @unknown default:
            assert(false)
            break
        }
        DispatchQueue.main.async {
            self.dc?.connectionStateChanged(state: state)
        }
    }
    
    fileprivate func receiveLoop() {
        assert(!Thread.current.isMainThread)

        self.connection.receive(minimumIncompleteLength: 2, maximumLength: 65534) { [weak self] (data, _, _, error) in
            guard let self = self else { return }
            var received: String?
            if let data = data, let str = String.init(data: data, encoding: .ascii) {
                received = str
            }
            let waiter = self.receiveWaiter
            self.receiveWaiter = nil
            if let waiter = waiter {
                waiter(received)
            } else if let received = received {
                let _ = self.parseResponse(additionalReceived: received, responseLineRegex: nil)
            }

            if let error = error {
                DLog("DenonStreams receiveLoop(): error, falling off - \(error)")
                return
            }
            guard self.connection.state == .ready else {
                DLog("DenonStreams receiveLoop(): state=\(self.connection.state), falling off.")
                return
            }
            self.receiveLoop()
        }
    }
    
    func write(_ data: Data, timeoutBlock: (()->Void)?, _ completionBlock: @escaping (Error?)->Void) {
        self.queue.async {
            guard self.lock.try() else {
                if self.dc?.verbose == true { DLog("DenonStreams write did not get lock") }
                DispatchQueue.main.async { timeoutBlock?() }
                return
            }

            let millis = abs(Date.init().timeIntervalSince1970) * 1000.0
            self.lastOpMillis = millis
            self.queue.asyncAfter(deadline: .now() + self.TIMEOUT_TIME) { [weak self] in
                guard let self = self else { return }
                guard self.lastOpMillis == millis else { return }
                DLog("DenonStreams write TIMEOUT")
                self.lock.unlock()
                self.connection.cancel()
                DispatchQueue.main.async { timeoutBlock?() }
            }
            self.connection.send(content: data, completion: .contentProcessed({ [weak self] (error) in
                guard let self = self else { return }
                guard self.lastOpMillis == millis else {
                    DLog("DenonStreams write completed AFTER timeout")
                    return
                }
                self.lastOpMillis = abs(Date.init().timeIntervalSince1970) * 1000.0
                self.lock.unlock()
                if let error = error {
                    DLog("DenonStreams write ERROR: \(error)")
                }
                DispatchQueue.main.async {
                    completionBlock(error)
                }
            }))
        }
    }

    // reads until it gets a line that starts with responseLineRegex -- then reads til the end of that line.
    // can be the same line as the command (ie. 0 \r)
    func readLine(minLength: Int, responseLineRegex: String?, hasLock: Bool = false, timeoutBlock: (()->Void)?, _ completionBlock: @escaping (String?)->Void) {
        self.queue.async {
            if !hasLock {
                guard self.lock.try() else {
                    DispatchQueue.main.async { timeoutBlock?() }
                    return
                }
            }
            
            let millis = abs(Date.init().timeIntervalSince1970) * 1000.0
            self.lastOpMillis = millis
            if let responseLineRegex = responseLineRegex {
                // check if we already have a hit
                if let result = self.parseResponse(additionalReceived: nil, responseLineRegex: responseLineRegex) {
                    self.lock.unlock()
                    DispatchQueue.main.async {
                        completionBlock(result)
                    }
                    return
                }
            }

            self.queue.asyncAfter(deadline: .now() + self.TIMEOUT_TIME) { [weak self] in
                guard let self = self else { return }
                guard self.lastOpMillis == millis else { return }
                DLog("DenonStreams readLine TIMEOUT")
                self.lock.unlock()
                self.receiveWaiter = nil
                DispatchQueue.main.async { timeoutBlock?() }
            }

            if self.connection.state != .ready {
                self.lock.unlock()
                DispatchQueue.main.async {
                    completionBlock(nil)
                }
                return
            }
            
            assert(self.receiveWaiter == nil)
            self.receiveWaiter = { [weak self] (received) in
                guard let self = self else { return }

                // always call parseResponse if we have data, so we don't lose anything
                let result = self.parseResponse(additionalReceived: received, responseLineRegex: responseLineRegex)
                guard self.lastOpMillis == millis else {
                    self.lock.unlock()
                    return
                }
                self.lastOpMillis = abs(Date.init().timeIntervalSince1970) * 1000.0
                
                if let result = result {
                    self.lock.unlock()
                    DispatchQueue.main.async {
                        completionBlock(result)
                    }
                    return
                }
                guard let _ = responseLineRegex else {
                    self.lock.unlock()
                    DispatchQueue.main.async {
                        completionBlock(received)
                    }
                    return
                }
                if let _ = received {
                    self.readLine(minLength: minLength, responseLineRegex: responseLineRegex, hasLock: true, timeoutBlock: timeoutBlock, completionBlock)
                    return
                }
                
                DLog("DenonStreams readLine - nothing received")
                self.lock.unlock()
                DispatchQueue.main.async {
                    completionBlock(nil)
                }
            }
        }
    }
    
    fileprivate func parseResponse(additionalReceived: String?, responseLineRegex: String?) -> String? {
        let str = self.unprocessedReceived.appending(additionalReceived ?? "")
        self.unprocessedReceived = ""
        let lineCount = str.reduce(0, { $0 + ($1 == "\r" ? 1 : 0) })
        var lines = str.split(separator: "\r")
        guard lineCount > 0 && lines.count > 0 else {
            self.unprocessedReceived = str
            return nil
        }

        // handle: denon sends MV91, we receive only "blah\rBlah\rMV9" here
        var incomplete: String?
        if str.last != "\r" {
            DLog("*** DS: incomplete last line case, handling...")
            incomplete = String(lines.removeLast())
        }

        var retval: String?
        var linesNotParsedAsEvents: String?
        var sinceLastMatch: String?
        for i in 0..<lines.count {
            let line = lines[i]
            let parsedAsEvent = self.dc?.parseResponseHelper(line: line) == true
            if let responseLineRegex = responseLineRegex, line.range(of: responseLineRegex, options: .regularExpression) != nil {
                sinceLastMatch = nil
                retval = String.init(line)
            } else if retval != nil, !parsedAsEvent {
                sinceLastMatch = (sinceLastMatch ?? "") + line + "\r"
            } else if !parsedAsEvent {
                linesNotParsedAsEvents = (linesNotParsedAsEvents ?? "") + line + "\r"
            }
        }

        if retval != nil {
            if let sinceLastMatch = sinceLastMatch {
                self.unprocessedReceived = sinceLastMatch
                if self.dc?.verbose == true {
                    DLog("DenonStreams checkIfComplete: unprocessedReceived.count=\(self.unprocessedReceived.count),  found extra chars after last match:\n")
                    DLog(sinceLastMatch.replacingOccurrences(of: "\r", with: "\n"))
                }
            }
            return retval
        }
        self.unprocessedReceived = (linesNotParsedAsEvents ?? "") + (incomplete ?? "")
        if let linesNotParsedAsEvents = linesNotParsedAsEvents, self.dc?.verbose == true {
            DLog("DenonStreams checkIfComplete: unprocessedReceived.count=\(self.unprocessedReceived.count), extra chars:\n")
            DLog(linesNotParsedAsEvents.replacingOccurrences(of: "\r", with: "\n"))
        }
        return nil
    }
}
