//
//  Extensions.swift
//  DenonVolume
//
//  Created by Tim Carr on 4/29/20.
//  Copyright © 2020 Solodigitalis. All rights reserved.
//

import UIKit
import MediaPlayer

extension MPVolumeView {
    static func setVolume(_ volume: Float) -> Void {
        let volumeView = MPVolumeView()
        let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider

        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.01) {
            slider?.value = volume
        }
    }
}

extension UIImage {
    static func fromColor(_ color: UIColor) -> UIImage {
        let size = CGSize.init(width: 1, height: 1)
        UIGraphicsBeginImageContext(size)
        color.setFill()
        UIRectFill(CGRect.init(origin: .zero, size: size))
        let retval = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return retval ?? UIImage.init()
    }
}

extension UIGestureRecognizer.State : CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .began: return "began"
        case .cancelled: return "cancelled"
        case .changed: return "changed"
        case .ended: return "ended"
        case .failed: return "failed"
        case .possible: return "possible"
        @unknown default:
            return "unknown!"
        }
    }
}

extension Double {
    func round(nearest: Double) -> Double {
        let n = 1/nearest
        let numberToRound = self * n
        return numberToRound.rounded() / n
    }

    func floor(nearest: Double) -> Double {
        let intDiv = Double(Int(self / nearest))
        return intDiv * nearest
    }
}
