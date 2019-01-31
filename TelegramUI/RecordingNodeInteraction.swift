//
//  RecordingNodeInteraction.swift
//  TelegramUI
//
//  Created by Daniyar Salakhutdinov on 31/01/2019.
//  Copyright © 2019 Telegram. All rights reserved.
//

import UIKit

class RecordingNodeInteraction {
    
    let play: () -> Void
    let pause: () -> Void
    let stop: () -> Void
    let seek: (Double) -> Void
    
    init(play: @escaping () -> Void, pause: @escaping () -> Void, stop: @escaping () -> Void,
         seek: @escaping (Double) -> Void) {
        self.play = play
        self.pause = pause
        self.stop = stop
        self.seek = seek
    }
}
