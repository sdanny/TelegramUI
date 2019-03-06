//
//  Mocks.swift
//  TelegramUI
//
//  Created by Daniyar Salakhutdinov on 06/03/2019.
//  Copyright © 2019 Telegram. All rights reserved.
//

import UIKit
import Display

class MockController: UITableViewController {
    
    var barButtonDidSelect: (() -> Void)?
    
    @IBAction func barButtonItemDidSelect(_ sender: UIBarButtonItem) {
        barButtonDidSelect?()
        tabBarController?.dismiss(animated: true)
    }
}
