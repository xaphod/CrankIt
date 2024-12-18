//
//  HomeViewController.swift
//  DenonVolume
//
//  Created by Tim Carr on 4/29/20.
//  Copyright © 2020 Solodigitalis. All rights reserved.
//

import UIKit
import SDWebImage

class HomeViewController: UIViewController {
    var zone: Int {
        get { AppDelegate.shared.zone }
        set {
            AppDelegate.shared.zone = newValue
            self.multiEqButton.isEnabled = newValue == 1
            self.updateSource(source: newValue == 2 ? self.denon?.zone2Source : self.denon?.lastSource, isZone2: newValue == 2)
        }
    }
    
    var denon: DenonController? {
        get {
            return AppDelegate.shared.denon
        }
        set {
            AppDelegate.shared.denon = newValue
        }
    }
    
    var panSlowly = false {
        didSet {
            let isMuted = self.zone == 2 ? self.denon?.zone2Mute : self.denon?.lastMute
            let isPoweredOff = self.zone == 2 ? self.denon?.zone2Power == false : self.denon?.lastPower == false
            if isMuted == true || isPoweredOff {
                return
            }
            let bgView = self.zone == 2 ? self.z2BackgroundView : self.volumeBackgroundView
            let fgView = self.zone == 2 ? self.z2ForegroundView : self.volumeForegroundView
            bgView!.layer.borderColor = panSlowly ? Colors.yellow.cgColor : Colors.reverseTint.cgColor
            fgView!.backgroundColor = panSlowly ? Colors.yellow : Colors.reverseTint
        }
    }
    var panBeginning = false
    var volumeAtStartOfPan: Double?
    var volumeLastDesiredInPan: Double?
    var volumeLastSetInPan: Double?
    var volumeHeightConstraint: NSLayoutConstraint?
    
    let panSlowlyMultiplier: CGFloat = 4.0
    var minimumVolume: Double {
        get { self.denon?.minimumVolume ?? 40 }
    }
    var lowPreset: Double {
        get {
            if UserDefaults.standard.value(forKey: "hvc.lowPreset") == nil { return 40.0 }
            return UserDefaults.standard.double(forKey: "hvc.lowPreset")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "hvc.lowPreset")
        }
    }
    var medPreset: Double {
        get {
            if UserDefaults.standard.value(forKey: "hvc.medPreset") == nil { return 50.0 }
            return UserDefaults.standard.double(forKey: "hvc.medPreset")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "hvc.medPreset")
        }
    }
    var highPreset: Double {
        get {
            if UserDefaults.standard.value(forKey: "hvc.highPreset") == nil { return 60.0 }
            return UserDefaults.standard.double(forKey: "hvc.highPreset")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "hvc.highPreset")
        }
    }
    
    enum VolumeDisplayStyle: String {
        case db
        case zeroBottom
    }
    var volumeDisplayStyle: VolumeDisplayStyle {
        get {
            guard let styleStr = UserDefaults.standard.value(forKey: "hvc.volumeDisplayStyle") as? String, let style = VolumeDisplayStyle.init(rawValue: styleStr) else { return .db }
            return style
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "hvc.volumeDisplayStyle")
        }
    }
    
    let VOLUME_CORNER_RADIUS: CGFloat = 30.0
    fileprivate var impactFeedbackHeavy: UIImpactFeedbackGenerator!
    fileprivate var selectionFeedback: UISelectionFeedbackGenerator!
    
    private var masterBottomConstraintTouched = false
    @IBOutlet weak var masterBottomConstraintForVolumeControls: NSLayoutConstraint?
    
    @IBOutlet var buttons: [UIButton]!
    @IBOutlet weak var muteButton: UIButton!
    @IBOutlet var mainPanGesture: UIPanGestureRecognizer!
    @IBOutlet var z2PanGesture: UIPanGestureRecognizer!
    @IBOutlet var tapGesture: UITapGestureRecognizer!
    @IBOutlet var longPressGesture: UILongPressGestureRecognizer!
    
    @IBOutlet weak var volumeBackgroundView: UIView!
    @IBOutlet weak var volumeForegroundView: UIView!
    
    @IBOutlet weak var z2BackgroundView: UIView!
    @IBOutlet weak var z2ForegroundView: UIView!
    var z2VolumeHeightConstraint: NSLayoutConstraint?
    @IBOutlet weak var z2VolumeLabel: UILabel!
    
    @IBOutlet weak var buttonsStackview: UIStackView!
    @IBOutlet weak var surroundModeLabel: UILabel!
    @IBOutlet weak var volumeLabel: UILabel!
    @IBOutlet weak var volButtonHigh: UIButton!
    @IBOutlet weak var volButtonMed: UIButton?
    @IBOutlet weak var volButtonLow: UIButton?
    @IBOutlet weak var powerButton: UIButton!
    @IBOutlet weak var powerCoverView: UIView!
    @IBOutlet weak var powerCoverButton: UIButton!
    @IBOutlet weak var limitButton: UIButton!
    @IBOutlet weak var limitLineView: UIView!
    @IBOutlet weak var debugLabel: UILabel!
    @IBOutlet weak var coverView: UIView!
    @IBOutlet weak var sourcesButton: UIButton!
    @IBOutlet weak var settingsButton: UIButton!
    @IBOutlet weak var multiEqButton: UIButton!
    @IBOutlet weak var zoneSegment: UISegmentedControl!
    
    // HEOS
    fileprivate weak var heosStackview: UIStackView?
    fileprivate weak var heosImageview: UIImageView?
    fileprivate weak var heosTopLabel: UILabel?
    fileprivate weak var heosBottomLabel: UILabel?
    fileprivate weak var heosPlayButton: UIButton?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        DLog("UIScreen.main height = \(UIScreen.main.bounds.height)")
        if UIScreen.main.bounds.height < 665 { // iPhone SE1 / iphone 5S: 568
            self.buttonsStackview.spacing = 10
            self.volButtonMed?.removeFromSuperview()
        } else if UIScreen.main.bounds.height < 668 { // iphone 8 / SE2: 667
            self.buttonsStackview.spacing = 20
            self.volButtonMed?.removeFromSuperview()
        }
        
        self.debugLabel.text = ""
        self.mainPanGesture.delegate = self
        self.z2PanGesture.delegate = self
        self.tapGesture.delegate = self
        self.longPressGesture.delegate = self
        self.volumeForegroundView.clipsToBounds = true
        self.volumeBackgroundView.clipsToBounds = true
        self.z2ForegroundView.clipsToBounds = true
        self.z2BackgroundView.clipsToBounds = true
        
        let feedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle
        if #available(iOS 13.0, *) {
            feedbackStyle = .rigid
            self.powerButton.setImage(UIImage.init(systemName: "power"), for: .normal)
        } else {
            feedbackStyle = .heavy
            self.powerButton.setImage(UIImage.init(named: "power"), for: .normal)
        }
        let impactHeavy = UIImpactFeedbackGenerator.init(style: feedbackStyle)
        let selectFeedback = UISelectionFeedbackGenerator.init()
        self.impactFeedbackHeavy = impactHeavy
        self.selectionFeedback = selectFeedback
        
        if #available(iOS 13.0, *) {
            self.multiEqButton.setTitle(nil, for: .normal)
            self.settingsButton.setTitle(nil, for: .normal)
            self.debugLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            self.volumeLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            self.z2VolumeLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            self.surroundModeLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            self.powerCoverView.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.85)
            self.volButtonLow?.setTitle(nil, for: .normal)
            self.volButtonLow?.setImage(UIImage.init(systemName: "speaker.1.fill"), for: .normal)
            self.volButtonMed?.setTitle(nil, for: .normal)
            self.volButtonMed?.setImage(UIImage.init(systemName: "speaker.2.fill"), for: .normal)
            self.volButtonHigh.setTitle(nil, for: .normal)
            self.volButtonHigh.setImage(UIImage.init(systemName: "speaker.3.fill"), for: .normal)
        } else {
            self.surroundModeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            self.volumeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            self.z2VolumeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            self.debugLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            self.powerCoverView.backgroundColor = UIColor.white.withAlphaComponent(0.9)
        }
        self.surroundModeLabel.text = self.denon?.lastSurroundMode ?? "__"
        self.volumeLabel.text = "__"
        self.z2VolumeLabel.text = "__"
        self.sourcesButton.setTitle("__", for: .normal)
        self.setColors()
        self.limitButton.alpha = 0
        self.limitLineView.alpha = 0
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        NotificationCenter.default.addObserver(self, selector: #selector(self.appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.volumeChangedByButtons(notification:)), name: .volumeChangedByButton, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.nowPlayingChanged(notification:)), name: .nowPlayingChanged, object: nil)
        Logging.debugLabelAll = false
        //        Logging.debugLabel = self.debugLabel
        UIApplication.shared.isIdleTimerDisabled = true
        self.denon?.hvc = self
        self.updateStackviewConstraints()
        self.startConnection()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: .volumeChangedByButton, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        UIApplication.shared.isIdleTimerDisabled = false
        Logging.debugLabel = nil
        self.denon?.canReconnect = false
        self.denon?.disconnectAll()
        self.denon?.hvc = nil
        self.denon = nil
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard UIApplication.shared.applicationState != .background else { return }
        self.setColors()
        self.updateMuteState(isZone2: false)
        self.updateMuteState(isZone2: true)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.volumeBackgroundView.layer.borderWidth = 8
        self.volumeBackgroundView.layer.cornerRadius = VOLUME_CORNER_RADIUS
        self.z2BackgroundView.layer.borderWidth = 4
        self.z2BackgroundView.layer.cornerRadius = 20
    }
    
    var didEverResign = false
    @objc fileprivate func appDidBecomeActive() {
        DLog("*** became active")
        self.denon?.lastBecameActive = Date.init()
        if !self.didEverResign { return }
        self.denon?.readVolume()
    }
    
    @objc fileprivate func appWillResignActive() {
        self.didEverResign = true
        self.panSlowly = false
    }
    
    private func startConnection() {
        DLog("HVC startConnection: calling denon.connect()")
        denon?.connect() { (initialState) in
            assert(Thread.current.isMainThread)
            guard let initialState = initialState else {
                return
            }
            self.updateVolume(initialState.volume, isZone2: self.zone == 2)
            self.updateMuteState(muteState: initialState.isMuted, isZone2: self.zone == 2)
            self.updateSource(source: initialState.source, isZone2: self.zone == 2)
            self.updatePowerCoverView()
        }
    }
    
    func connectionStateChanged(isConnected: Bool) {
        if isConnected {
            DLog("***: hiding coverView, last active = \(abs((self.denon?.lastBecameActive ?? Date.init()).timeIntervalSinceNow))")
        }
        self.coverView.isHidden = isConnected
        self.updatePowerCoverView()
    }
    
    var stackviewConstraint: NSLayoutConstraint?
    func updateStackviewConstraints() {
        self.stackviewConstraint?.isActive = false
        let constraint = self.buttonsStackview.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.trailingAnchor, constant: -20)
        constraint.isActive = true
        self.stackviewConstraint = constraint
    }
    
    private func setColors() {
        self.buttons.forEach {
            $0.tintColor = Colors.tint
            $0.setTitleColor(Colors.tint, for: .normal)
        }
        self.settingsButton.tintColor = Colors.reverseTint
        self.settingsButton.setTitleColor(Colors.reverseTint, for: .normal)
        self.volumeBackgroundView.backgroundColor = Colors.tint
        self.volumeBackgroundView.layer.borderColor = Colors.reverseTint.cgColor
        self.volumeForegroundView.backgroundColor = Colors.reverseTint
        self.z2BackgroundView.backgroundColor = Colors.tint
        
        // assume zone 2 is off until we learn it isn't
        self.z2BackgroundView.layer.borderColor = Colors.darkGray.cgColor
        self.z2ForegroundView.backgroundColor = Colors.darkGray
        
        self.volButtonLow?.backgroundColor = Colors.green
        self.volButtonMed?.backgroundColor = Colors.yellow
        self.volButtonHigh.backgroundColor = Colors.orange
    }
    
    @IBAction func multiEqButtonPressed(_ sender: UIButton) {
        let alert = UIAlertController.init(title: "MultiEQ Setting", message: nil, preferredStyle: .actionSheet)
        alert.popoverPresentationController?.sourceView = sender.superview
        alert.popoverPresentationController?.sourceRect = sender.frame
        MultiEQSetting.values.forEach { (eq) in
            alert.addAction(UIAlertAction.init(title: eq.displayLong, style: .default, handler: { (_) in
                eq.setValue(denon: self.denon, nil)
            }))
        }
        alert.addAction(UIAlertAction.init(title: "Cancel", style: .cancel, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
    
    @IBAction func reconnectPressed(_ sender: Any) {
        self.startConnection()
    }
    
    @IBAction func settingsButtonPressed(_ sender: UIButton) {
        self.openAlertSettings(sender: sender)
    }
    
    @IBAction func discoveryPressed(_ sender: Any) {
        self.navigationController?.popViewController(animated: true)
    }
    
    @objc func volumeChangedByButtons(notification: Notification) {
        guard let userInfo = notification.userInfo, let v = userInfo["volume"] as? Double else {
            assert(false)
            return
        }
        self.selectionFeedback.selectionChanged()
        self.updateVolume(v, isZone2: self.zone == 2)
    }
    
    @IBAction func setVolLow(_ sender: Any) {
        self.denon?.setVolume(self.lowPreset, isZone2: self.zone == 2) { (v, _) in
            self.selectionFeedback.selectionChanged()
            self.updateVolume(v, isZone2: self.zone == 2)
        }
    }
    @IBAction func setVolMedium(_ sender: Any) {
        self.denon?.setVolume(self.medPreset, isZone2: self.zone == 2) { (v, _) in
            self.selectionFeedback.selectionChanged()
            self.updateVolume(v, isZone2: self.zone == 2)
        }
    }
    @IBAction func setVolHigh(_ sender: Any) {
        self.denon?.setVolume(self.highPreset, isZone2: self.zone == 2) { (v, _) in
            self.selectionFeedback.selectionChanged()
            self.updateVolume(v, isZone2: self.zone == 2)
        }
    }
    
    @IBAction func sourcesButtonPressed(_ sender: Any) {
        let alert = UIAlertController.init(title: "Select Source", message: "Not all sources are available on all receivers.", preferredStyle: .actionSheet)
        InputSourceSetting.Input.allCases.map { InputSourceSetting.init(input: $0, isZone2: self.zone == 2) }.forEach { source in
            guard source.isHidden == false && source.input != .unknown else { return }
            alert.addAction(UIAlertAction.init(title: source.displayLong, style: .default, handler: { (_) in
                source.setValue(denon: self.denon) { (err) in
                    if let _ = err {
                        self.showTryAgainAlert()
                        return
                    }
                    self.updateSource(source: source, isZone2: self.zone == 2)
                }
            }))
        }
        alert.addAction(UIAlertAction.init(title: "Cancel", style: .cancel, handler: nil))
        alert.popoverPresentationController?.sourceView = self.sourcesButton.superview
        alert.popoverPresentationController?.sourceRect = self.sourcesButton.frame
        self.present(alert, animated: true, completion: nil)
    }
    
    @IBAction func muteButtonPressed(_ sender: Any) {
        self.denon?.toggleMuteState(isZone2: self.zone == 2) { (err) in
            if err == nil {
                self.impactFeedbackHeavy.impactOccurred()
            }
            self.updateMuteState(muteState: nil, isZone2: self.zone == 2)
        }
    }
    
    @IBAction func powerButtonLongPressed(_ sender: UILongPressGestureRecognizer) {
        self.denon?.setPowerToStandby()
    }
    
    @IBAction func powerCoverButtonPressed(_ sender: UIButton) {
        self.zone = 1
        self.powerButtonPressed(sender)
    }
    
    @IBAction func powerButtonPressed(_ sender: UIButton) {
        guard let dc = self.denon else { return }
        self.buttons.forEach { $0.isEnabled = false }
        
        dc.togglePowerState(isZone2: self.zone == 2) { (initialState) in
            guard let initialState = initialState else {
                self.buttons.forEach { $0.isEnabled = true }
                self.showTryAgainAlert()
                return
            }
            self.impactFeedbackHeavy.impactOccurred()
            self.updateVolume(initialState.volume, isZone2: false)
            if let vol = dc.zone2Volume {
                self.updateVolume(vol, isZone2: true)
            }
            self.updateMuteState(muteState: initialState.isMuted, isZone2: false)
            if let muted = dc.zone2Mute {
                self.updateMuteState(muteState: muted, isZone2: true)
            }
            self.updateSource(source: initialState.source, isZone2: self.zone == 2)
            self.updatePowerCoverView()
            self.buttons.forEach { $0.isEnabled = true }
        }
    }
    
    func powerStateDidUpdate() {
        DLog("powerStateDidUpdate()")
        guard let dc = self.denon else { return }
        self.updateVolume(dc.lastVolume, isZone2: false)
        self.updateVolume(dc.zone2Volume, isZone2: true)
        self.updateMuteState(muteState: dc.lastMute, isZone2: false)
        self.updateMuteState(muteState: dc.zone2Mute, isZone2: true)
        self.updateSource(source: self.zone == 2 ? dc.zone2Source : dc.lastSource, isZone2: self.zone == 2)
        self.updatePowerCoverView()
    }
    
    private func updatePowerCoverView() {
        guard let dc = self.denon else { return }
        let anyHasPower = dc.lastPower == true || dc.zone2Power == true
        self.powerCoverView.isHidden = anyHasPower
    }
    
    @IBAction func limitButtonPressed(_ sender: Any) {
        self.changeVolumeLimit()
    }
    
    func updateSource(source: InputSourceSetting?, isZone2: Bool) {
        guard let source = source else { return }
        if (self.zone == 1 && isZone2) || (self.zone == 2 && !isZone2) { return }
        if source.displayShort.count == 0 {
            self.sourcesButton.setTitle("SRC", for: .normal)
            return
        }
        self.sourcesButton.setTitle(source.displayShort, for: .normal)
    }
    
    func updateSurroundMode() {
        assert(Thread.current.isMainThread)
        if let surround = self.denon?.lastSurroundMode, let eq = self.denon?.lastEQ {
            self.surroundModeLabel.text = eq.displayLong + ", " + surround
        } else if let surround = self.denon?.lastSurroundMode {
            self.surroundModeLabel.text = surround
        } else if let eq = self.denon?.lastEQ {
            self.surroundModeLabel.text = eq.displayLong
        } else {
            self.surroundModeLabel.text = "__"
        }
    }
    
    func updateVolume(_ volume: Double?, isZone2: Bool) {
        let zoneText = isZone2 ? "Zone 2\n" : "Main Zone\n"
        let isMuted = isZone2 ? self.denon?.zone2Mute : self.denon?.lastMute
        self.view.layoutIfNeeded()
        assert(Thread.current.isMainThread)
        if self.denon?.verbose ?? false { DLog("HVC updateVolume: \(String(describing: volume)), isMuted=\(String(describing: isMuted)), isZone2=\(isZone2)") }
        let volumeLabel = isZone2 ? self.z2VolumeLabel : self.volumeLabel
        if isMuted == true {
            volumeLabel?.text = zoneText + "Muted"
        }
        let powerBool = isZone2 ? self.denon?.zone2Power : self.denon?.lastPower
        if powerBool == false {
            // For this case we want show same state of the volume slider as when it is muted; that will happen in updateMuteState()
            volumeLabel?.text = zoneText + "OFF"
        }
        
        guard let volume = volume ?? (isZone2 ? self.denon?.zone2Volume : self.denon?.lastVolume) else { return }
        if isMuted != true && powerBool != false {
            volumeLabel?.text = zoneText + self.volumeToString(vol: volume)
        }
        let bgView = isZone2 ? self.z2BackgroundView : self.volumeBackgroundView
        let bgHeight = bgView!.bounds.height
        let fgHeight: CGFloat
        if volume <= self.minimumVolume {
            fgHeight = 0
        } else {
            fgHeight = CGFloat((volume - self.minimumVolume) / ((self.denon?.volumeMax ?? 98) - self.minimumVolume)) * bgHeight
        }
        let constraint = isZone2 ? self.z2VolumeHeightConstraint : self.volumeHeightConstraint
        constraint?.isActive = false
        let fgView = isZone2 ? self.z2ForegroundView : self.volumeForegroundView
        let newConstraint = fgView!.heightAnchor.constraint(equalToConstant: fgHeight)
        newConstraint.isActive = true
        if isZone2 {
            self.z2VolumeHeightConstraint = newConstraint
        } else {
            self.volumeHeightConstraint = newConstraint
        }
        fgView!.setNeedsLayout()
        UIView.animate(withDuration: 0.1) {
            self.view.layoutIfNeeded()
            if !isZone2 {
                self.limitLineView.alpha = self.volumeIsMax(volume) && powerBool != false ? 1.0 : 0
                self.limitButton.alpha = self.volumeIsMax(volume) && powerBool != false ? 1.0 : 0
            }
        }
    }
    
    func updateMuteState(muteState: Bool? = nil, isZone2: Bool) {
        let work: (Bool?, Error?)->Void = { (muted, error) in
            let mutedImage: UIImage
            if #available(iOS 13.0, *) {
                mutedImage = UIImage.init(systemName: "speaker.slash.fill")!
            } else {
                mutedImage = UIImage.init(named: "mute_on")!
            }
            
            guard let muted = muted else {
                DLog("updateMuteState ERROR: \(String(describing: error))")
                return
            }
            self.muteButton.setImage(mutedImage, for: .normal)
            
            let powerBool = isZone2 ? self.denon?.zone2Power : self.denon?.lastPower
            let fgView = isZone2 ? self.z2ForegroundView : self.volumeForegroundView
            let bgView = isZone2 ? self.z2BackgroundView : self.volumeBackgroundView
            fgView!.backgroundColor = powerBool == false || muted ? Colors.darkGray : Colors.reverseTint
            bgView!.layer.borderColor = powerBool == false || muted ? Colors.darkGray.cgColor : Colors.reverseTint.cgColor
            self.updateVolume(isZone2 ? self.denon?.zone2Volume : self.denon?.lastVolume, isZone2: isZone2)
        }
        if let muteState = muteState {
            work(muteState, nil)
            return
        }
        self.denon?.readMuteState() { [weak self] (error) in
            work(isZone2 ? self?.denon?.zone2Mute : self?.denon?.lastMute, error)
        }
    }
    
    @IBAction func zoneSegmentChanged(_ sender: UISegmentedControl) {
        if sender.selectedSegmentIndex == 0 {
            self.zone = 2
        } else if sender.selectedSegmentIndex == 1 {
            self.zone = 1
        }
    }
    
    // DOUBLE TAP TO MUTE
    @IBAction func handleDoubleTap(_ sender: UITapGestureRecognizer) {
        self.muteButtonPressed(sender)
    }
    
    @IBAction func handleZ2BGTap(_ sender: UITapGestureRecognizer) {
        self.zoneSegment.selectedSegmentIndex = 0
        self.zone = 2
    }
    
    @IBAction func handleZ1BGTap(_ sender: UITapGestureRecognizer) {
        self.zoneSegment.selectedSegmentIndex = 1
        self.zone = 1
    }
    
    // does have ended state
    @IBAction func handleLongPress(_ sender: UILongPressGestureRecognizer) {
        switch sender.state {
        case .began:
            self.panSlowly = true
            self.impactFeedbackHeavy?.impactOccurred()
        case .ended:
            self.panSlowly = false
        default:
            break
        }
    }
    
    @IBAction func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        let isZone2 = gesture == self.z2PanGesture
        let powerBool = isZone2 ? self.denon?.zone2Power : self.denon?.lastPower
        if powerBool == false {
            return
        }
        
        if self.panBeginning {
            self.panBeginning = false
            self.selectionFeedback.selectionChanged()
            self.denon?.readVolume { (err) in
                if let err = err { DLog("HVC readVolume ERROR: \(err)") }
                let volBool = isZone2 ? self.denon?.zone2Volume : self.denon?.lastVolume
                if let vol = volBool {
                    DLog("HVC handlePan beginning readVolume = \(vol)")
                    self.volumeAtStartOfPan = vol
                }
            }
        } else if gesture.state == .ended {
            self.selectionFeedback.selectionChanged()
        }

        guard let volume = self.volumeAtStartOfPan else { return }
        
        let coords = gesture.translation(in: nil)
        let bgView = isZone2 ? self.z2BackgroundView : self.volumeBackgroundView
        var heightRange = bgView!.bounds.height
        if self.panSlowly {
            heightRange *= self.panSlowlyMultiplier
        }
        let percentOfFullVolumeRange = (-coords.y / heightRange)
        let amountToAdd = Double(percentOfFullVolumeRange) * ((self.denon?.volumeMax ?? 98) - self.minimumVolume)
        var result = volume + amountToAdd
        if self.volumeIsMax(result) {
            self.impactFeedbackHeavy.impactOccurred()
        } else if ((result-2.0)...result).contains(self.minimumVolume) {
            self.impactFeedbackHeavy.impactOccurred()
        }
        result = min(result, self.denon?.maxAllowedSafeVolume ?? self.denon?.volumeMax ?? 98)
        result = max(result, 0) // self.minimumVolume)
        result = result.round(nearest: isZone2 ? 1 : 0.5) // zone 2 cannot due half DBs like 33.5
        
        if self.volumeLastDesiredInPan == result {
            return
        }
        self.volumeLastDesiredInPan = result
        
        self.denon?.setVolume(result, isZone2: isZone2) { (v, err) in
            if let err = err {
                if self.denon?.verbose ?? false { DLog("pan setVolume, ERROR: \(err)") }
            }
            if let v = v, v != result {
                DLog("HVC handlePan setVolume: mismatch \(v) != \(result)")
            }
            self.volumeLastSetInPan = v
            self.updateVolume(v, isZone2: isZone2)
        }
    }
    
    fileprivate func volumeIsMax(_ v: Double) -> Bool {
        if self.denon?.maxAllowedSafeVolume == self.denon?.volumeMax { return false }
        if let max = self.denon?.maxAllowedSafeVolume, ((v...(v+4.0)).contains(max) || v > max) {
            return true
        }
        return false
    }
    
    private func volumeToString(vol: Double) -> String {
        switch self.volumeDisplayStyle {
        case .db:
            return "\(vol-80) dB"
        case .zeroBottom:
            return "\(vol)"
        }
    }
    
    // NOW PLAYING
    @objc func nowPlayingChanged(notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let song = userInfo[NowPlayingMediaNotificationKeys.song] as? String,
            let artist = userInfo[NowPlayingMediaNotificationKeys.artist] as? String
        else {
            assert(false)
            return
        }
        
        // optionals
        // let album = userInfo[NowPlayingMediaNotificationKeys.album] as? String
        let mediaUrl = userInfo[NowPlayingMediaNotificationKeys.mediaUrl] as? URL
        
        self.addHEOSDisplayComponents()
        
        self.heosImageview?.sd_setImage(with: mediaUrl)
        self.heosTopLabel?.text = artist
        self.heosBottomLabel?.text = song
    }
    
    private func addHEOSDisplayComponents() {
        if self.masterBottomConstraintTouched {
            return
        }
        self.masterBottomConstraintTouched = true
        let height: CGFloat = 140
        self.masterBottomConstraintForVolumeControls?.constant = height // move up volume controls for now playing view
        
        // remove two butons from main/right buttons so the power button isn't right near heos controls
        if UIDevice.current.userInterfaceIdiom != .pad {
            self.volButtonMed?.removeFromSuperview()
            self.volButtonLow?.removeFromSuperview()
        }
        
        // HORIZONTAL stackview
        let container = UIStackView.init()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.axis = .horizontal
        container.distribution = .fill
        container.spacing = 6
        container.translatesAutoresizingMaskIntoConstraints = false
        self.view.insertSubview(container, belowSubview: self.powerCoverView)
        self.heosStackview = container
        var constraints = [
            container.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 8),
            container.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            container.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -8),
            container.heightAnchor.constraint(equalToConstant: height - 18)
        ]
        
        let albumView = UIView.init()
        let imageview = UIImageView.init()
        imageview.translatesAutoresizingMaskIntoConstraints = false
        albumView.addSubview(imageview)

        let albumArtButton = UIButton.init()
        albumArtButton.translatesAutoresizingMaskIntoConstraints = false
        albumArtButton.addTarget(self, action: #selector(self.heosAlbumArtTouched(_:)), for: .touchUpInside)
        albumView.addSubview(albumArtButton)
        
        self.heosImageview = imageview
        constraints += [
            albumView.widthAnchor.constraint(equalTo: albumView.heightAnchor, multiplier: 1),
            albumArtButton.leadingAnchor.constraint(equalTo: albumView.leadingAnchor),
            albumArtButton.trailingAnchor.constraint(equalTo: albumView.trailingAnchor),
            albumArtButton.topAnchor.constraint(equalTo: albumView.topAnchor),
            albumArtButton.bottomAnchor.constraint(equalTo: albumView.bottomAnchor),
            imageview.leadingAnchor.constraint(equalTo: albumView.leadingAnchor),
            imageview.trailingAnchor.constraint(equalTo: albumView.trailingAnchor),
            imageview.topAnchor.constraint(equalTo: albumView.topAnchor),
            imageview.bottomAnchor.constraint(equalTo: albumView.bottomAnchor),
        ]
        container.addArrangedSubview(albumView)

        // rightView has labels, controls
        let rightView = UIView.init()
        container.addArrangedSubview(rightView)
        
        let topLabel = UILabel.init()
        topLabel.translatesAutoresizingMaskIntoConstraints = false
        let bottomLabel = UILabel.init()
        bottomLabel.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 13.0, *) {
            topLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            bottomLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        } else {
            topLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
            bottomLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        }
        rightView.addSubview(topLabel)
        rightView.addSubview(bottomLabel)
        self.heosTopLabel = topLabel
        self.heosBottomLabel = bottomLabel
        
        let buttonStack = UIStackView.init()
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.axis = .horizontal
        buttonStack.spacing = 4
        rightView.addSubview(buttonStack)
        constraints += [
            buttonStack.centerYAnchor.constraint(equalTo: imageview.centerYAnchor),
            buttonStack.leadingAnchor.constraint(equalTo: rightView.leadingAnchor, constant: 4),
            buttonStack.heightAnchor.constraint(equalToConstant: 52),
            buttonStack.trailingAnchor.constraint(lessThanOrEqualTo: rightView.trailingAnchor),
        ]
        
        let prevButton = UIButton.init()
        prevButton.translatesAutoresizingMaskIntoConstraints = false
        prevButton.layer.cornerRadius = 26
        prevButton.setImage(UIImage.init(named: "skip-back-circle")!.sd_tintedImage(with: Colors.reverseTint), for: .normal)
        prevButton.addTarget(self, action: #selector(self.prevButtonPressed(_:)), for: .touchUpInside)
        constraints.append(prevButton.widthAnchor.constraint(equalToConstant: 52))
        buttonStack.addArrangedSubview(prevButton)
        
        let playButton = UIButton.init()
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.layer.cornerRadius = 26
        playButton.setImage(UIImage.init(named: "play-circle")!.sd_tintedImage(with: Colors.reverseTint), for: .normal)
        playButton.addTarget(self, action: #selector(self.playPauseButtonPressed(_:)), for: .touchUpInside)
        constraints.append(playButton.widthAnchor.constraint(equalToConstant: 52))
        buttonStack.addArrangedSubview(playButton)
        self.heosPlayButton = playButton
        
        let nextButton = UIButton.init()
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.layer.cornerRadius = 26
        nextButton.setImage(UIImage.init(named: "skip-forward-circle")!.sd_tintedImage(with: Colors.reverseTint), for: .normal)
        nextButton.addTarget(self, action: #selector(self.nextButtonPressed(_:)), for: .touchUpInside)
        constraints.append(nextButton.widthAnchor.constraint(equalToConstant: 52))
        buttonStack.addArrangedSubview(nextButton)
        
        // label constraints
        constraints += [
            bottomLabel.bottomAnchor.constraint(equalTo: rightView.bottomAnchor, constant: 1),
            bottomLabel.leadingAnchor.constraint(equalTo: rightView.leadingAnchor, constant: 8),
            bottomLabel.trailingAnchor.constraint(lessThanOrEqualTo: rightView.trailingAnchor, constant: 0),
            topLabel.bottomAnchor.constraint(equalTo: bottomLabel.topAnchor, constant: -4),
            topLabel.leadingAnchor.constraint(equalTo: rightView.leadingAnchor, constant: 8),
            topLabel.trailingAnchor.constraint(lessThanOrEqualTo: rightView.trailingAnchor, constant: 0),
        ]
        
        NSLayoutConstraint.activate(constraints)
        self.view.setNeedsLayout()
        self.view.layoutIfNeeded()
    }
    
    @objc func prevButtonPressed(_ sender: UIButton) {
        guard let denon = self.denon, let stream = denon.stream1255 else { return }
        denon.heosHandler.playPrevious(stream: stream)
        self.selectionFeedback.selectionChanged()
    }
    
    @objc func nextButtonPressed(_ sender: UIButton) {
        guard let denon = self.denon, let stream = denon.stream1255 else { return }
        denon.heosHandler.playNext(stream: stream)
        self.selectionFeedback.selectionChanged()
    }
    
    @objc func playPauseButtonPressed(_ sender: UIButton) {
        guard let denon = self.denon, let stream = denon.stream1255 else { return }
        if denon.heosHandler.playState == .play {
            denon.heosHandler.setPause(stream: stream)
        } else {
            denon.heosHandler.setPlay(stream: stream)
        }
        self.selectionFeedback.selectionChanged()
    }
    
    func updatePlayPauseButton(playState: DenonHEOSHandler.PlayState) {
        guard let playButton = self.heosPlayButton else { return }
        if playState == .play {
            playButton.setImage(UIImage.init(named: "pause-circle")!.sd_tintedImage(with: Colors.reverseTint), for: .normal)
        } else {
            playButton.setImage(UIImage.init(named: "play-circle")!.sd_tintedImage(with: Colors.reverseTint), for: .normal)
        }
    }
    
    @objc func heosAlbumArtTouched(_ sender: UIButton) {
        guard let image = self.heosImageview?.image else { return }
        let vc = AlbumArtViewController.init(image: image)
        self.present(vc, animated: true)
    }
}

extension HomeViewController : UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let view = gestureRecognizer.view
        let loc = touch.location(in: view)
        let subview = view?.hitTest(loc, with: nil)
        if let subview = subview, subview.isKind(of: UIButton.self) {
            return false
        }
        // yes, everywhere except buttons
        return true
    }
    
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if !self.coverView.isHidden || !self.powerCoverView.isHidden {
            return false
        }
        
        if gestureRecognizer === self.mainPanGesture || gestureRecognizer == self.z2PanGesture {
            panBeginning = true
            volumeAtStartOfPan = nil
            self.impactFeedbackHeavy.prepare()
            self.selectionFeedback.prepare()
        }
        return true
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if (gestureRecognizer == self.mainPanGesture || gestureRecognizer == self.z2PanGesture) && otherGestureRecognizer == self.longPressGesture {
            return true
        }
        if (otherGestureRecognizer == self.mainPanGesture || gestureRecognizer == self.z2PanGesture) && gestureRecognizer == self.longPressGesture {
            return true
        }
        return false
    }
}
