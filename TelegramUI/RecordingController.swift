//
//  RecordingController.swift
//  TelegramUI
//
//  Created by Daniyar Salakhutdinov on 31/01/2019.
//  Copyright © 2019 Telegram. All rights reserved.
//

import UIKit
import Display
import Postbox
import TelegramCore
import SwiftSignalKit
import AVFoundation

public class RecordingController: NSObject, AVAudioPlayerDelegate {
    
    private(set) var controllerNode: RecordingControllerNode!
    
    private let _ready = Promise<Bool>(false)
    public var ready: Promise<Bool> {
        return self._ready
    }
    
    private let playerStatusPromise = Promise<MediaPlayerStatus>(.zero)
    
    private let account: Account
    private var presentationData: PresentationData

    private(set) var callId: Int64?
    private(set) var peer: Peer?
    
    private var player: AVAudioPlayer?
    private var timer: SwiftSignalKit.Timer?
    private let store: RecordingsStore = .shared
    
    private var seekId = 0

    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public init(account: Account) {
        self.account = account
        self.presentationData = account.telegramApplicationContext.currentPresentationData.with { $0 }
        
        super.init()
        
        let interaction = RecordingNodeInteraction(switchPlayingState: switchPlayingState, stop: stop, seek: seek)
        self.controllerNode = RecordingControllerNode(account: account, presentationData: presentationData, interaction: interaction)
        self._ready.set(.single(true))
    }
    
    func update(callId: Int64, peer: Peer) {
        if self.callId == callId,
            self.peer?.id == peer.id { return }
        self.callId = callId
        self.peer = peer
        playerStatusPromise.set(.single(.zero))
        controllerNode.update(peer: peer, playerStatus: playerStatusPromise.get())
        
        guard let url = store.recordingUrlForCall(withId: callId),
            let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.delegate = self
        self.player = player
        self.timer = SwiftSignalKit.Timer(timeout: 0.1, repeat: true, completion: timerDidFire, queue: .mainQueue())
    }
    
    private func timerDidFire() {
        updatePlayerStatus()
    }
    
    public func switchPlayingState() -> Void {
        guard let player = player else { return }
        let isPlaying = player.isPlaying
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    public func play() {
        controllerNode.isHidden = false
        player?.play()
        updatePlayerStatus()
        timer?.start()
        controllerNode.isPlaying = true
    }
    
    public func pause() {
        player?.pause()
        updatePlayerStatus()
        controllerNode.isPlaying = false
    }
    
    public func stop() {
        player?.stop()
        updatePlayerStatus()
        reset()
    }
    
    private func reset() {
        player = nil
        callId = nil
        peer = nil
        timer?.invalidate()
        controllerNode.isHidden = true
    }
    
    public func seek(_ value: Double) {
        guard let player = player else { return }
        seekId += 1
        player.currentTime = value
        updatePlayerStatus()
    }
    
    private func updatePlayerStatus() {
        guard let player = player else { return }
        let timestamp = player.currentTime
        let isPlaying: MediaPlayerPlaybackStatus = player.isPlaying ? .playing : .paused
        let status = MediaPlayerStatus(generationTimestamp: 0, duration: player.duration, dimensions: .zero, timestamp: timestamp, baseRate: 1.0, seekId: seekId, status: isPlaying)
        playerStatusPromise.set(.single(status))
    }
    
    // MARK: player delegate
    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        reset()
    }

}

extension MediaPlayerStatus {
    static let zero = MediaPlayerStatus.init(generationTimestamp: 0, duration: 0, dimensions: .zero,
                                             timestamp: 0, baseRate: 0, seekId: 0, status: .paused)
}
