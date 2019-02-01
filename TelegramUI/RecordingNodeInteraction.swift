//
//  RecordingNodeInteraction.swift
//  TelegramUI
//
//  Created by Daniyar Salakhutdinov on 31/01/2019.
//  Copyright © 2019 Telegram. All rights reserved.
//

import UIKit

class RecordingNodeInteraction {
    
    let switchPlayingState: () -> Void
    let stop: () -> Void
    let seek: (Double) -> Void
    
    init(switchPlayingState: @escaping () -> Void, stop: @escaping () -> Void,
         seek: @escaping (Double) -> Void) {
        self.switchPlayingState = switchPlayingState
        self.stop = stop
        self.seek = seek
    }
}
