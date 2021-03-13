//
//  Colors.swift
//  DenonVolume
//
//  Created by Tim Carr on 5/1/20.
//  Copyright © 2020 Solodigitalis. All rights reserved.
//

import UIKit

// https://www.avanderlee.com/swift/dark-mode-support-ios/
public enum Colors {
    public static let label: UIColor = {
        if #available(iOS 13.0, *) {
            return UIColor.label
        } else {
            return .black
        }
    }()
    
    public static let red = UIColor.systemRed
    public static let orange = UIColor.systemOrange
    public static let yellow = UIColor.systemYellow
    public static let green = UIColor.systemGreen
    public static let darkGray = UIColor.darkGray
    
    public static let reverseTint: UIColor = {
        if #available(iOS 13, *) {
            return UIColor { (UITraitCollection: UITraitCollection) -> UIColor in
                if UITraitCollection.userInterfaceStyle == .dark {
                    return .white
                } else {
                    return .black
                }
            }
        }
        return .black
    }()
    public static let tint: UIColor = {
        if #available(iOS 13, *) {
            return UIColor { (UITraitCollection: UITraitCollection) -> UIColor in
                if UITraitCollection.userInterfaceStyle == .dark {
                    return .black
                } else {
                    return .white
                }
            }
        }
        return .white
    }()

}

