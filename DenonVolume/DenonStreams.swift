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
    static let TIMEOUT_TIME: TimeInterval = 2
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
            DLog("stateUpdateHandler: ready (connected), time since app became active = \(abs((self.dc?.lastBecameActive ?? Date.init()).timeIntervalSinceNow))")
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
                if self.dc?.verbose == true {
                    DLog("received, has waiter=\(self.receiveWaiter != nil): \(received)")
                }
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
    
    private struct QueueItem {
        var data: Data
        var timeoutTime: TimeInterval
        var timeoutBlock: (()->Void)?
        var minLength: Int
        var responseLineRegex: String?
        var completionBlock: (String?, Error?)->Void
    }
    private var writeQueue = [QueueItem]()

    func writeAndRead(_ data: Data, canQueue: Bool, timeoutTime: TimeInterval = DenonStreams.TIMEOUT_TIME, timeoutBlock: (()->Void)?, minLength: Int, responseLineRegex: String?, _ completionBlock: @escaping (String?, Error?)->Void) {
        self.queue.async {
            let hasLock = self.lock.try()
            if !hasLock, !canQueue {
                return // drop it
            }
            let queueItem = QueueItem.init(data: data, timeoutTime: timeoutTime, timeoutBlock: timeoutBlock, minLength: minLength, responseLineRegex: responseLineRegex, completionBlock: completionBlock)
            self.writeQueue.insert(queueItem, at: 0)
            if hasLock {
                let _ = self.writeNext()
            } else {
                DLog("DenonStreams write: lock busy for \(String(describing: String.init(data: queueItem.data, encoding: .ascii)?.dropLast(1))), added to queue. Queue length = \(self.writeQueue.count)")
            }
        }
    }

    // PRE: ON SELF.WRITEQUEUE, ON SELF.LOCK
    private func writeNext() -> Bool {
        guard self.writeQueue.count > 0 else {
            return false
        }
        let queueItem = self.writeQueue.removeLast()
        if self.dc?.verbose == true {
            DLog("DenonStreams writeNext: \(String(describing: String.init(data: queueItem.data, encoding: .ascii)?.dropLast(1)))")
        }

        let millis = abs(Date.init().timeIntervalSince1970) * 1000.0
        self.lastOpMillis = millis
        self.queue.asyncAfter(deadline: .now() + Self.TIMEOUT_TIME) { [weak self] in
            guard let self = self else { return }
            guard self.lastOpMillis == millis else { return }
            DLog("DenonStreams writeNext TIMEOUT")
            self.lock.unlock()
            self.connection.cancel()
            DispatchQueue.main.async {
                queueItem.timeoutBlock?()
            }
        }

        self.connection.send(content: queueItem.data, completion: .contentProcessed({ [weak self] (error) in
            guard let self = self else { return }
            guard self.lastOpMillis == millis else {
                DLog("DenonStreams writeNext completed AFTER timeout")
                return
            }
            self.lastOpMillis = abs(Date.init().timeIntervalSince1970) * 1000.0
            if let error = error {
                DLog("DenonStreams writeNext ERROR: \(error)")
                if !self.writeNext() {
                    self.lock.unlock()
                }

                DispatchQueue.main.async {
                    queueItem.completionBlock(nil, error)
                }
                return
            }

            self._readLine(minLength: queueItem.minLength, responseLineRegex: queueItem.responseLineRegex, timeoutTime: queueItem.timeoutTime, timeoutBlock: queueItem.timeoutBlock, queueItem.completionBlock)
        }))
        
        return true
    }

    // PRE: ON SELF.LOCK
    // reads until it gets a line that starts with responseLineRegex -- then reads til the end of that line.
    // can be the same line as the command (ie. 0 \r)
    private func _readLine(minLength: Int, responseLineRegex: String?, timeoutTime: TimeInterval, timeoutBlock: (()->Void)?, _ completionBlock: @escaping (String?, Error?)->Void) {
        self.queue.async {
            let millis = abs(Date.init().timeIntervalSince1970) * 1000.0
            self.lastOpMillis = millis
            if let responseLineRegex = responseLineRegex {
                // check if we already have a hit
                if let result = self.parseResponse(additionalReceived: nil, responseLineRegex: responseLineRegex) {
                    if !self.writeNext() {
                        self.lock.unlock()
                    }
                    DispatchQueue.main.async {
                        completionBlock(result, nil)
                    }
                    return
                }
            }

            if self.connection.state != .ready {
                if !self.writeNext() {
                    self.lock.unlock()
                }
                DispatchQueue.main.async {
                    completionBlock(nil, CommandError.noStream)
                }
                return
            }
            
            self.queue.asyncAfter(deadline: .now() + timeoutTime) { [weak self] in
                guard let self = self else { return }
                guard self.lastOpMillis == millis else { return }
                self.receiveWaiter = nil
                if !self.writeNext() {
                    self.lock.unlock()
                }
                DispatchQueue.main.async {
                    timeoutBlock?()
                }
            }

            assert(self.receiveWaiter == nil)
            self.receiveWaiter = { [weak self] (received) in
                guard let self = self else { return }

                // always call parseResponse if we have data, so we don't lose anything
                let result = self.parseResponse(additionalReceived: received, responseLineRegex: responseLineRegex)
                guard self.lastOpMillis == millis else {
                    if !self.writeNext() {
                        self.lock.unlock()
                    }
                    return
                }
                self.lastOpMillis = abs(Date.init().timeIntervalSince1970) * 1000.0
                
                if let result = result {
                    if !self.writeNext() {
                        self.lock.unlock()
                    }
                    DispatchQueue.main.async {
                        completionBlock(result, nil)
                    }
                    return
                }
                guard let _ = responseLineRegex else {
                    if !self.writeNext() {
                        self.lock.unlock()
                    }
                    DispatchQueue.main.async {
                        completionBlock(received, nil)
                    }
                    return
                }
                if let _ = received {
                    self._readLine(minLength: minLength, responseLineRegex: responseLineRegex, timeoutTime: timeoutTime, timeoutBlock: timeoutBlock, completionBlock)
                    return
                }
                
                DLog("DenonStreams readLine - nothing received")
                if !self.writeNext() {
                    self.lock.unlock()
                }
                DispatchQueue.main.async {
                    completionBlock(nil, nil)
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
        return nil
    }
}
