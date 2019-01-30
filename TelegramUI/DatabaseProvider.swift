//
//  DatabaseProvider.swift
//  TelegramUI
//
//  Created by Daniyar Salakhutdinov on 30/01/2019.
//  Copyright © 2019 Telegram. All rights reserved.
//

import Foundation
import RealmSwift

public struct RealmProvider {
    static let version: UInt64 = 0
    
    static let migration: MigrationBlock = { migration, oldVersion in
        // this is where future realm versions migrations should be
    }
}
