//
//  RootViewController.swift
//  DenonVolume
//
//  Created by Tim Carr on 5/1/20.
//  Copyright © 2020 Solodigitalis. All rights reserved.
//

import UIKit
import SwiftSSDP
import XMLCoder

let CONNECTION_DELAY = 0.3

class RootViewController : UIViewController {
    fileprivate let verboseDiscovery = false
    fileprivate let discovery = SSDPDiscovery.defaultDiscovery
    fileprivate var discoverySession: SSDPDiscoverySession?
    fileprivate let delayTime = 5.0
    fileprivate var waitAlert: UIAlertController?
    fileprivate let session = URLSession.init(configuration: .default)
    fileprivate let discoveryGroup = DispatchGroup.init()
    fileprivate var receivers = [Receiver]()
    fileprivate static let receiversUserDefaultsKey = "receivers.v1"
    fileprivate var initialCheckComplete = false

    @IBOutlet weak var debugLabel: UILabel!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!

    override func viewDidLoad() {
        super.viewDidLoad()
        self.activityIndicator.color = Colors.reverseTint
        self.activityIndicator.isHidden = true
        
        if #available(iOS 13.0, *) {
            self.debugLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        } else {
            self.debugLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        #if DEBUG
        Logging.debugLabel = self.debugLabel
        #endif
        
        self.loadReceiversFromDefaults()
        self.go()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.receivers = []
    }
    
    func loadReceiversFromDefaults() {
        if let data = UserDefaults.standard.value(forKey: RootViewController.receiversUserDefaultsKey) as? Data, let receivers = try? JSONDecoder.init().decode([Receiver].self, from: data) {
            self.receivers = receivers
        }
    }
    
    func saveReceiversToDefaults() {
        guard self.receivers.count > 0 else {
            RootViewController.clearReceiversFromDefaults()
            return
        }
        if let data = try? JSONEncoder.init().encode(self.receivers) {
            UserDefaults.standard.setValue(data, forKey: RootViewController.receiversUserDefaultsKey)
        }
    }
    
    static func clearReceiversFromDefaults() {
        UserDefaults.standard.setValue(nil, forKey: RootViewController.receiversUserDefaultsKey)
    }
    
    fileprivate func go(skipDelay: Bool = false, demoMode: Bool = false) {
        assert(Thread.current.isMainThread)
        if demoMode {
            let denon = DenonController.init(demoMode: true)
            AppDelegate.shared.denon = denon
            self.performSegue(withIdentifier: "segueToHome", sender: nil)
            return
        }

        if self.receivers.count > 1 || self.initialCheckComplete {
            self.activityIndicator.isHidden = true
            let alert = UIAlertController.init(title: "Pick your receiver", message: nil, preferredStyle: UIDevice.current.userInterfaceIdiom == .pad ? .alert : .actionSheet)
            self.receivers.forEach { (receiver) in
                alert.addAction(UIAlertAction.init(title: receiver.description, style: .default, handler: { (_) in
                    self.startWithReceiver(receiver)
                }))
            }
            alert.addAction(UIAlertAction.init(title: "Manually enter IP address", style: .default, handler: { (_) in
                self.enterIPAddress()
            }))
            alert.addAction(UIAlertAction.init(title: "Search again", style: .default, handler: { (_) in
                self.doDiscovery()
            }))
            self.present(alert, animated: true, completion: nil)
            return
        }
        
        self.initialCheckComplete = true

        if self.receivers.count == 1 {
            // initial delay seems necessary on iO13 / iPhone XS: otherwise ECONNREFUSED after stream state = ready
            self.activityIndicator.isHidden = false
            self.activityIndicator.startAnimating()
            
            if skipDelay {
                self.startWithReceiver(self.receivers[0])
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + CONNECTION_DELAY) { [weak self] in
                    guard let self = self else { return }
                    self.startWithReceiver(self.receivers[0])
                }
            }
            return
        }
        
        self.doDiscovery()
    }
    
    fileprivate func startWithReceiver(_ receiver: Receiver) {
        let denon = DenonController.init(receiver: receiver)
        AppDelegate.shared.denon = denon
        self.performSegue(withIdentifier: "segueToHome", sender: nil)
    }
    
    func doDiscovery() {
        DLog("RVC startDiscovery()")
        self.receivers = []
        RootViewController.clearReceiversFromDefaults()

        self.activityIndicator.isHidden = true
        let alert = UIAlertController.init(title: "Searching network...", message: "Looking for Denon & Marantz receivers on the network. This takes \(self.delayTime) seconds, please wait.", preferredStyle: .alert)
        self.waitAlert = alert
        self.present(alert, animated: true, completion: nil)
        let target = SSDPSearchTarget.deviceType(schema: SSDPSearchTarget.upnpOrgSchema, deviceType: "MediaRenderer", version: 1)
        let request = SSDPMSearchRequest.init(delegate: self, searchTarget: target)
        do {
            self.discoverySession = try self.discovery.startDiscovery(request: request, timeout: self.delayTime)
        } catch {
            DLog("RVC startDiscovery: ERROR thrown - \(error)")
            self.discoveryFinished()
        }
    }
    
    func discoveryFinished() {
        self.discoveryGroup.notify(queue: .main) {
            self.saveReceiversToDefaults()

            self.waitAlert?.dismiss(animated: true, completion: nil)
            self.waitAlert = nil
            
            let alert = UIAlertController.init(title: "\(self.receivers.count) receivers found", message: "Please choose a receiver, or search again.", preferredStyle: UIDevice.current.userInterfaceIdiom == .pad ? .alert : .actionSheet)
            self.receivers.forEach { (receiver) in
                alert.addAction(UIAlertAction.init(title: receiver.description, style: .default, handler: { (_) in
                    self.startWithReceiver(receiver)
                }))
            }
            alert.addAction(UIAlertAction.init(title: "Manually enter IP address", style: .default, handler: { (_) in
                self.enterIPAddress()
            }))
            if self.receivers.count == 0 {
                alert.addAction(UIAlertAction.init(title: "Demo mode", style: .default, handler: { (_) in
                    self.go(skipDelay: true, demoMode: true)
                }))
            }
            alert.addAction(UIAlertAction.init(title: "Search again", style: .default, handler: { (_) in
                self.doDiscovery()
            }))
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    func enterIPAddress() {
        let alert = UIAlertController.init(title: "Enter an IP address", message: "You can enter an IP address or a host name. Please note there is no input checking, so please check your input carefully.", preferredStyle: .alert)
        alert.addTextField { (tf) in
            tf.autocorrectionType = .no
            tf.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction.init(title: "Cancel", style: .cancel, handler: { (_) in
            self.discoveryFinished()
        }))
        alert.addAction(UIAlertAction.init(title: "OK", style: .default, handler: { (_) in
            guard let tf = alert.textFields?[0], let text = tf.text, text.count > 0 else {
                self.discoveryFinished()
                return
            }
            let manualReceiver = Receiver.init(ipAddress: text, device: Receiver.Device.init(friendlyName: "Manually entered IP", manufacturer: "", modelDescription: nil, modelName: nil, modelNumber: nil))
            self.receivers.append(manualReceiver)
            self.saveReceiversToDefaults()
            self.startWithReceiver(manualReceiver)
        }))
        self.present(alert, animated: true, completion: nil)
    }
}

extension RootViewController : SSDPDiscoveryDelegate {
    func discoveredDevice(response: SSDPMSearchResponse, session: SSDPDiscoverySession) {
        DLog("RVC discoveredDevice: \(response) - loading \(response.location)")
        self.discoveryGroup.enter()
        response.retrieveLocation(with: self.session) { (data, err) in
            assert(Thread.current.isMainThread)
            defer {
                self.discoveryGroup.leave()
            }
            guard let data = data else {
                DLog("RVC discoveredDevice: could not load XML from \(response.location), error = \(String(describing: err))")
                return
            }
            let decoder = XMLDecoder.init()
            decoder.shouldProcessNamespaces = true
            do {
                if self.verboseDiscovery {
                    DLog("RVC discoveredDevice: loaded raw XML:")
                    DLog(String.init(data: data, encoding: .utf8) ?? "could not make utf8 string!")
                }
                var receiver = try decoder.decode(Receiver.self, from: data)
                if receiver.worksWithCrankIt {
                    receiver.ipAddress = response.location.host
                    self.receivers.append(receiver)
                    return
                }
                DLog("RVC discoveredDevice: \(response.location) is not a Denon receiver.")
            } catch {
                DLog("RVC discoveredDevice: could not parse XML from \(response.location), error = \(String(describing: error))")
            }
        }
    }
    
    func discoveredService(response: SSDPMSearchResponse, session: SSDPDiscoverySession) {
        DLog("RVC discoveredService: \(response) - ignoring.")
    }
    
    func closedSession(_ session: SSDPDiscoverySession) {
        DLog("RVC closedSession")
        self.discoveryFinished()
    }
}
