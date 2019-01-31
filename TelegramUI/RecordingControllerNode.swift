//
//  RecordingControllerNode.swift
//  TelegramUI
//
//  Created by Daniyar Salakhutdinov on 31/01/2019.
//  Copyright © 2019 Telegram. All rights reserved.
//

import UIKit
import Display
import TelegramCore
import Postbox
import SwiftSignalKit

private let avatarFont: UIFont = UIFont(name: ".SFCompactRounded-Semibold", size: 16.0)!

class RecordingControllerNode: ASDisplayNode {
    
    private let account: Account
    private var presentationData: PresentationData
    private let theme: PresentationTheme
    private let interaction: RecordingNodeInteraction
    private var params: (peer: Peer, playerStatus: Signal<MediaPlayerStatus, NoError>)?
    var contentSize: CGSize? {
        didSet {
            setNeedsDisplay()
        }
    }
    
    private let playbackStatus = Promise<MediaPlayerStatus>()
    private let isPlaying = Promise<Bool>(false)
    
    private let backgroundNode: ASDisplayNode
    private let topStripeNode: ASDisplayNode
    private let avatarNode: AvatarNode
    private let timeNode: TextNode
    private let progressNode: MediaPlayerScrubbingNode
    
    init(account: Account, presentationData: PresentationData, interaction: RecordingNodeInteraction) {
        self.account = account
        self.presentationData = presentationData
        self.theme = presentationData.theme
        self.interaction = interaction
        
        backgroundNode = ASDisplayNode()
        backgroundNode.isLayerBacked = true
        
        topStripeNode = ASDisplayNode()
        topStripeNode.isLayerBacked = true
        
        avatarNode = AvatarNode(font: avatarFont)
        
        timeNode = TextNode()
        
        progressNode = MediaPlayerScrubbingNode(content: .standard(lineHeight: 2.0, lineCap: .round, scrubberHandle: .none, backgroundColor: .clear, foregroundColor: self.theme.rootController.navigationBar.accentTextColor))
        progressNode.hitTestSlop = UIEdgeInsetsMake(-10.0, 0.0, -10.0, 0.0)
        progressNode.seek = interaction.seek
        
        super.init()
        
        addSubnode(backgroundNode)
        addSubnode(avatarNode)
        addSubnode(timeNode)
        addSubnode(progressNode)
        addSubnode(topStripeNode)
    }
    
    public func update(peer: Peer, playerStatus: Signal<MediaPlayerStatus, NoError>) {
        self.params = (peer, playerStatus)
        setNeedsDisplay()
    }
    
    override func layout() {
        guard let params = params,
            let contentSize = contentSize else { return }
        backgroundNode.backgroundColor = UIColor.white.withAlphaComponent(0.7)
        backgroundNode.frame = CGRect(origin: .zero, size: contentSize)
        
        topStripeNode.backgroundColor = .lightGray
        topStripeNode.frame = CGRect(origin: .zero, size: CGSize(width: contentSize.width, height: 1))
        
        avatarNode.frame = CGRect(origin: CGPoint(x: 16, y: 5.0), size: CGSize(width: 40.0, height: 40.0))
        avatarNode.setPeer(account: account, peer: params.peer)
        
        progressNode.status = params.playerStatus
    }
}
