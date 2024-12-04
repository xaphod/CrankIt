//
//  AlbumArtViewController.swift
//  DenonVolume
//
//  Created by Tim Carr on 2024-12-03.
//  Copyright © 2024 Solodigitalis. All rights reserved.
//

import UIKit

class AlbumArtViewController : UIViewController {
    let image: UIImage
    
    init(image: UIImage) {
        self.image = image
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var modalPresentationStyle: UIModalPresentationStyle {
        get {
            return .overCurrentContext
        }
        set {}
    }
    
    override var modalTransitionStyle: UIModalTransitionStyle {
        get {
            return .crossDissolve
        }
        set {}
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = UIColor.black.withAlphaComponent(0.9)
        
        let imageview = UIImageView.init()
        imageview.translatesAutoresizingMaskIntoConstraints = false
        imageview.image = self.image
        imageview.contentMode = .scaleAspectFit
        self.view.addSubview(imageview)
        
        let exitButton = UIButton.init()
        exitButton.translatesAutoresizingMaskIntoConstraints = false
        exitButton.addTarget(self, action: #selector(self.exitButtonPressed(_:)), for: .touchUpInside)
        self.view.addSubview(exitButton)
        
        NSLayoutConstraint.activate([
            imageview.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            imageview.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
            imageview.widthAnchor.constraint(equalTo: self.view.widthAnchor, multiplier: 0.95),
            imageview.heightAnchor.constraint(equalTo: self.view.heightAnchor, multiplier: 0.95),
            
            exitButton.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            exitButton.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            exitButton.topAnchor.constraint(equalTo: self.view.topAnchor),
            exitButton.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
        ])
    }
    
    @objc func exitButtonPressed(_ sender: UIButton) {
        self.dismiss(animated: true)
    }
}
