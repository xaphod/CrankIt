//
//  Logging.swift
//  DenonVolume
//
//  Created by Tim Carr on 5/1/20.
//  Copyright © 2020 Solodigitalis. All rights reserved.
//

import UIKit

func DLog(_ format: String, _ args: CVarArg...) {
    Logging.LLog(format, args)
}

class Logging {
    weak static var debugLabel: UILabel?
    static var debugLabelAll = true
    private static var lineMinus3: String?
    private static var lineMinus2: String?
    private static var lineMinus1: String?
    
    static func LLog(_ format: String, _ args: CVarArg...) {
        #if DEBUG
        NSLog(format, args)
        DispatchQueue.main.async {
            if debugLabelAll {
                debugLabel?.text = (debugLabel?.text ?? "") + "\n" + format
                return
            }
            debugLabel?.text = "\(Logging.lineMinus3 ?? "")\n\(Logging.lineMinus2 ?? "")\n\(Logging.lineMinus1 ?? "")\n\(format)"
            Logging.lineMinus3 = Logging.lineMinus2
            Logging.lineMinus2 = Logging.lineMinus1
            Logging.lineMinus1 = format
        }
        #endif
    }
}
