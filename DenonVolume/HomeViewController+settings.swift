//
//  HomeViewController+settings.swift
//  DenonVolume
//
//  Created by Tim Carr on 5/7/20.
//  Copyright © 2020 Solodigitalis. All rights reserved.
//

import UIKit

extension HomeViewController {
    func openAlertSettings(sender: UIView) {
        let alert = UIAlertController.init(title: "Crank It", message: "This list scrolls up and down eh?", preferredStyle: .actionSheet)
        alert.popoverPresentationController?.sourceView = sender.superview
        alert.popoverPresentationController?.sourceRect = sender.frame
        alert.addAction(UIAlertAction.init(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction.init(title: "Talk to us on our forums", style: .default, handler: { (_) in
            UIApplication.shared.open(URL.init(string: "https://wifibooth.com/community/viewforum.php?f=11")!, options: [:], completionHandler: nil)
        }))
        alert.addAction(UIAlertAction.init(title: "Privacy Policy", style: .default, handler: { (_) in
            UIApplication.shared.open(URL.init(string: "https://soloslides.app/privacy/")!, options: [:], completionHandler: nil)
        }))
        alert.addAction(UIAlertAction.init(title: "Reveal dark secrets", style: .default, handler: { (_) in
            self.showTips()
        }))
        let nextVolStyle: VolumeDisplayStyle
        let volStyleDesc: String
        switch self.volumeDisplayStyle {
        case .db:
            nextVolStyle = .zeroBottom
            volStyleDesc = "0-98"
        case .zeroBottom: nextVolStyle = .db
            volStyleDesc = "dB"
        }

        alert.addAction(UIAlertAction.init(title: "Change volume style to \(volStyleDesc)", style: .default, handler: { (_) in
            self.volumeDisplayStyle = nextVolStyle
            self.updateVolume(self.denon?.lastVolume)
        }))
        alert.addAction(UIAlertAction.init(title: "Change volume limit (\(self.denon?.maxAllowedSafeVolume ?? 80))", style: .default, handler: { (_) in
            self.changeVolumeLimit()
        }))
        alert.addAction(UIAlertAction.init(title: "Change high volume preset", style: .default, handler: { (_) in
            self.changePreset(key: "high")
        }))
        alert.addAction(UIAlertAction.init(title: "Change medium volume preset", style: .default, handler: { (_) in
            self.changePreset(key: "medium")
        }))
        alert.addAction(UIAlertAction.init(title: "Change low volume preset", style: .default, handler: { (_) in
            self.changePreset(key: "low")
        }))
        alert.addAction(UIAlertAction.init(title: "Change minimum volume (\(self.denon?.minimumVolume ?? 30))", style: .default, handler: { (_) in
            self.changePreset(key: "minimum")
        }))
        alert.addAction(UIAlertAction.init(title: "Hide / show input sources", style: .default, handler: { (_) in
            self.inputSourcesShowOrHide(sender: sender)
        }))
        alert.addAction(UIAlertAction.init(title: "Rename input sources", style: .default, handler: { (_) in
            self.inputSourcesRename(sender: sender)
        }))
        if AudioController.shared.filename == "sweep" {
            alert.addAction(UIAlertAction.init(title: "Stop continuous frequency sweeps", style: .destructive, handler: { (_) in
                AudioController.shared.filename = nil
                AudioController.shared.setupPlayer()
            }))
        } else {
            alert.addAction(UIAlertAction.init(title: "Play continuous frequency sweeps", style: .default, handler: { (_) in
                AudioController.shared.disabled = false
                AudioController.shared.filename = "sweep"
                AudioController.shared.setupPlayer()
            }))
        }
        let title = AudioController.shared.disabled ? "Enable audio so vol buttons work" : "Disable audio so music doesn't stop"
        alert.addAction(UIAlertAction.init(title: title, style: .default, handler: { (_) in
            AudioController.shared.disabled = !AudioController.shared.disabled
        }))
        self.present(alert, animated: true, completion: nil)
    }
    
    func inputSourcesShowOrHide(sender: UIView) {
        let alert = UIAlertController.init(title: "Select source to show or hide", message: "This controls which sources are shown in the list when you hit the source button.", preferredStyle: .actionSheet)
        InputSourceSetting.Input.allCases.map { InputSourceSetting.init(input: $0, isZone2: self.zone == 2) }.forEach { source in
            guard source.input != .unknown else { return }
            var source = source
            alert.addAction(UIAlertAction.init(title: (source.isHidden ? "Show " : "Hide ") + source.displayLong, style: source.isHidden ? .default : .destructive, handler: { (_) in
                source.isHidden = !source.isHidden
                self.inputSourcesShowOrHide(sender: sender)
            }))
        }
        alert.addAction(UIAlertAction.init(title: "Done", style: .cancel, handler: nil))
        alert.popoverPresentationController?.sourceView = sender.superview
        alert.popoverPresentationController?.sourceRect = sender.frame
        self.present(alert, animated: true, completion: nil)
    }
    
    func inputSourcesRename(sender: UIView) {
        let alert = UIAlertController.init(title: "Select a source to rename", message: nil, preferredStyle: .actionSheet)
        InputSourceSetting.Input.allCases.map { InputSourceSetting.init(input: $0, isZone2: self.zone == 2) }.forEach { source in
            guard source.isHidden == false && source.input != .unknown else { return }
            alert.addAction(UIAlertAction.init(title: source.displayLong, style: .default, handler: { (_) in
                self.inputSourceRename(source: source, sender: sender)
            }))
        }
        alert.addAction(UIAlertAction.init(title: "Cancel", style: .default, handler: nil))
        alert.popoverPresentationController?.sourceView = sender.superview
        alert.popoverPresentationController?.sourceRect = sender.frame
        self.present(alert, animated: true, completion: nil)
    }
    
    func inputSourceRename(source: InputSourceSetting, sender: UIView) {
        let alert = UIAlertController.init(title: "Rename \(source.displayLong)", message: "The first textfield controls how the source appears in the list. The second textfield controls how the source button on the home screen shows the source -- this should be 4 characters or less.", preferredStyle: .alert)
        alert.addTextField { (textfield) in
            textfield.text = source.displayLong
        }
        alert.addTextField { (textfield) in
            textfield.text = source.displayShort
        }
        let handler: ((UIAlertAction) -> Void) = { (_) in self.inputSourcesRename(sender: sender) }
        alert.addAction(UIAlertAction.init(title: "Cancel", style: .cancel, handler: handler))
        alert.addAction(UIAlertAction.init(title: "Rename", style: .default, handler: { (_) in
            guard
                let textfieldLong = alert.textFields?[0],
                let textfieldShort = alert.textFields?[1],
                let textLong = textfieldLong.text,
                textLong.count > 0,
                let textShort = textfieldShort.text,
                textShort.count > 0
            else { return }
            source.rename(short: textShort, long: textLong)
            self.inputSourcesRename(sender: sender)
        }))
        self.present(alert, animated: true, completion: nil)
    }
    
    func changeVolumeLimit() {
        let alert = UIAlertController.init(title: "Change Volume Limit", message: "This sets the maximum volume you can swipe to. You can still go beyond this point using the volume preset buttons." + "\n\n" + "Please enter a number between 0 and 98.\n0 = -80 dB\n80 = 0 dB\n98 = speakers probably blown apart", preferredStyle: .alert)
        alert.addTextField { (tf) in
            tf.keyboardType = .decimalPad
            tf.text = String(self.denon?.maxAllowedSafeVolume ?? 80)
        }
        alert.addAction(UIAlertAction.init(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction.init(title: "OK", style: .default, handler: { (_) in
            guard let str = alert.textFields?[0].text, let val = Double(str)?.round(nearest: 0.5) else {
                return
            }
            guard val >= 0 && val <= 98 else {
                let failAlert = UIAlertController.init(title: "Oops", message: "That's not a number between 0 and 98. Please try again.", preferredStyle: .alert)
                failAlert.addAction(UIAlertAction.init(title: "OK", style: .default, handler: { (_) in
                    self.changeVolumeLimit()
                }))
                self.present(failAlert, animated: true, completion: nil)
                return
            }
            
            self.denon?.maxAllowedSafeVolume = val
        }))
        self.present(alert, animated: true, completion: nil)
    }
    
    func changePreset(key: String) {
        let alert = UIAlertController.init(title: "Change \(key) volume preset", message: "Please enter a number between 0 and 98.\n0 = -80 dB\n80 = 0 dB\n98 = speakers probably blown apart", preferredStyle: .alert)
        alert.addTextField { (tf) in
            tf.keyboardType = .decimalPad
            switch (key) {
            case "low": tf.text = String(self.lowPreset)
            case "medium": tf.text = String(self.medPreset)
            case "high": tf.text = String(self.highPreset)
            case "minimum": tf.text = String(self.denon?.minimumVolume ?? 30)
            default: break
            }
        }
        alert.addAction(UIAlertAction.init(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction.init(title: "OK", style: .default, handler: { (_) in
            if let str = alert.textFields?[0].text, let val = Double(str)?.round(nearest: 0.5) {
                guard val >= 0 && val <= 98 else {
                    let failAlert = UIAlertController.init(title: "Oops", message: "That's not a number between 0 and 98. Please try again.", preferredStyle: .alert)
                    failAlert.addAction(UIAlertAction.init(title: "OK", style: .default, handler: { (_) in
                        self.changePreset(key: key)
                    }))
                    self.present(failAlert, animated: true, completion: nil)
                    return
                }
                
                switch (key) {
                case "low": self.lowPreset = val
                case "medium": self.medPreset = val
                case "high": self.highPreset = val
                case "minimum":
                    self.denon?.minimumVolume = val
                    self.updateVolume(self.denon?.lastVolume)

                default: break
                }
            }
        }))
        self.present(alert, animated: true, completion: nil)
    }
    
    func showTips() {
        let alert = UIAlertController.init(title: "Hawt Tips", message: """
Here are things you can do that might not be obvious:

- you can swipe up and down anywhere on the screen (does not have to be within the bounds of the volume bar)

- you can double-tap to mute

- if you hold your finger down for a second before starting to swipe (ie. long-press then swipe), the bar turns yellow and the volume change rate is slower. This is for when you want to make minor changes to the volume

- after enabling the volume buttons (last option on the menu) you can use the phone's volume up/down buttons even when the app is in the background, or when the phone is locked / screen off
"""
            , preferredStyle: .alert)
        alert.addAction(UIAlertAction.init(title: "OK", style: .cancel, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }

    func showTryAgainAlert() {
        let alert = UIAlertController.init(title: "Please try again", message: "There was a problem issuing the command, please try again.", preferredStyle: .alert)
        alert.addAction(UIAlertAction.init(title: "OK", style: .default, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
}
