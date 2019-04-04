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
private let titleFont = Font.regular(17.0)
private let timeFont = Font.regular(14.0)

class RecordingControllerNode: ASDisplayNode {
    
    private let account: Account
    private var presentationData: PresentationData
    private let theme: PresentationTheme
    private let interaction: RecordingNodeInteraction
    private var params: (peer: Peer, playerStatus: Signal<MediaPlayerStatus, NoError>)?
    var contentSize: CGSize? {
        didSet {
            setNeedsLayout()
        }
    }
    
    private let backgroundNode: ASDisplayNode
    private let topStripeNode: ASDisplayNode
    private let avatarNode: AvatarNode
    private let titleNode: TextNode
    private let timeNode: TextNode
    private let progressNode: MediaPlayerScrubbingNode
    private let playButtonNode: HighlightableButtonNode
    private let stopButtonNode: HighlightableButtonNode
    
    private var timeDisposable: Disposable?
    
    var isPlaying: Bool = false {
        didSet {
            let icon = !isPlaying ? PresentationResourcesCallList.playButton(self.theme) : PresentationResourcesRootController.navigationPlayerPauseIcon(self.theme)
            playButtonNode.setImage(icon, for: .normal)
        }
    }
    
    init(account: Account, presentationData: PresentationData, interaction: RecordingNodeInteraction) {
        self.account = account
        self.presentationData = presentationData
        self.theme = presentationData.theme
        self.interaction = interaction
        
        backgroundNode = ASDisplayNode()
        backgroundNode.isLayerBacked = true
        backgroundNode.backgroundColor = self.theme.chatList.backgroundColor
        
        topStripeNode = ASDisplayNode()
        topStripeNode.isLayerBacked = true
        
        avatarNode = AvatarNode(font: avatarFont)
        titleNode = TextNode()
        timeNode = TextNode()
        
        let foregroundColor = self.theme.rootController.navigationBar.accentTextColor
        
        progressNode = MediaPlayerScrubbingNode(content: .standard(lineHeight: 4.0, lineCap: .round, scrubberHandle: .circle, backgroundColor: .clear, foregroundColor: foregroundColor))
        progressNode.hitTestSlop = UIEdgeInsetsMake(-10.0, 0.0, -10.0, 0.0)
        progressNode.seek = interaction.seek
        progressNode.enableScrubbing = true
        
        playButtonNode = HighlightableButtonNode()
        playButtonNode.hitTestSlop = UIEdgeInsets(top: -6.0, left: -6.0, bottom: -6.0, right: -10.0)
        let playIcon = PresentationResourcesCallList.playButton(self.theme)
        playButtonNode.setImage(playIcon, for: .normal)
        
        stopButtonNode = HighlightableButtonNode()
        let closeIcon = PresentationResourcesRootController.navigationPlayerCloseButton(self.theme)
        stopButtonNode.setImage(closeIcon, for: .normal)
        stopButtonNode.hitTestSlop = UIEdgeInsets(top: -6.0, left: -6.0, bottom: -6.0, right: -10.0)
        
        super.init()
        
        stopButtonNode.addTarget(self, action: #selector(stop(_:)), forControlEvents: .touchUpInside)
        playButtonNode.addTarget(self, action: #selector(playPause(_:)), forControlEvents: .touchUpInside)
        
        addSubnode(backgroundNode)
        addSubnode(avatarNode)
        addSubnode(titleNode)
        addSubnode(timeNode)
        addSubnode(progressNode)
        addSubnode(topStripeNode)
        addSubnode(playButtonNode)
        addSubnode(stopButtonNode)
    }
    
    deinit {
        timeDisposable?.dispose()
    }
    
    public func update(peer: Peer, playerStatus: Signal<MediaPlayerStatus, NoError>) {
        self.params = (peer, playerStatus)
        setNeedsLayout()
    }
    
    override func layout() {
        guard let params = params,
            let contentSize = contentSize else { return }
        backgroundNode.frame = CGRect(origin: .zero, size: contentSize)
        
        topStripeNode.backgroundColor = .lightGray
        topStripeNode.frame = CGRect(origin: .zero, size: CGSize(width: contentSize.width, height: 1))
        
        let makeTitleLayout = TextNode.asyncLayout(titleNode)
        
        let sideInset: CGFloat = 12
        let avatarSize: CGFloat = 40
        avatarNode.frame = CGRect(origin: CGPoint(x: sideInset, y: 5.0), size: CGSize(width: avatarSize, height: avatarSize))
        avatarNode.setPeer(account: account, theme: presentationData.theme, peer: params.peer)
        
        let titleSize = CGSize(width: contentSize.width - sideInset * 3 - avatarSize, height: 20)
        titleNode.frame = CGRect(origin: CGPoint(x: sideInset * 2 + avatarSize, y: 4), size: titleSize)
        timeNode.frame = CGRect(origin: CGPoint(x: sideInset * 2 + avatarSize, y: avatarSize - 20 + 4), size: titleSize)
        
        progressNode.status = params.playerStatus
        progressNode.frame = CGRect(origin: CGPoint(x: sideInset, y: contentSize.height - sideInset - 6), size: CGSize(width: contentSize.width - sideInset * 2, height: 20))
        
        let buttonSize = CGSize(width: 20, height: 20)
        stopButtonNode.frame = CGRect(origin: CGPoint(x: contentSize.width - sideInset - buttonSize.width, y: 4), size: buttonSize)
        playButtonNode.frame = CGRect(origin: CGPoint(x: contentSize.width - (sideInset * 3) - buttonSize.width, y: 4), size: buttonSize)
        
        let titleColor = self.theme.list.itemPrimaryTextColor
        var titleAttributedString: NSAttributedString?
        if let user = params.peer as? TelegramUser {
            if let firstName = user.firstName, let lastName = user.lastName, !firstName.isEmpty, !lastName.isEmpty {
                let string = NSMutableAttributedString()
                string.append(NSAttributedString(string: firstName, font: titleFont, textColor: titleColor))
                string.append(NSAttributedString(string: " ", font: titleFont, textColor: titleColor))
                string.append(NSAttributedString(string: lastName, font: titleFont, textColor: titleColor))
                titleAttributedString = string
            } else if let firstName = user.firstName, !firstName.isEmpty {
                titleAttributedString = NSAttributedString(string: firstName, font: titleFont, textColor: titleColor)
            } else if let lastName = user.lastName, !lastName.isEmpty {
                titleAttributedString = NSAttributedString(string: lastName, font: titleFont, textColor: titleColor)
            } else {
                titleAttributedString = NSAttributedString(string: presentationData.strings.User_DeletedAccount, font: titleFont, textColor: titleColor)
            }
        }
        let (_, titleApply) = makeTitleLayout(TextNodeLayoutArguments(attributedString: titleAttributedString, backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: titleSize, alignment: .natural, lineSpacing: 0, cutout: nil, insets: .zero))
        let _ = titleApply()
        
        timeDisposable = params.playerStatus.start(next: { status in
            let timestamp = status.timestamp
            var string = ""
            let hours = Int(floor(timestamp / 1.hours))
            if hours > 1 {
                string = "\(hours):"
            }
            let minutes = timestamp.truncatingRemainder(dividingBy: 1.hours) / 1.minutes
            let seconds = timestamp.truncatingRemainder(dividingBy: 1.minutes)
            let minutesString = String(format: "%02d", Int(floor(minutes)))
            let secondsString = String(format: "%02d", Int(floor(seconds)))
            string += "\(minutesString):\(secondsString)"
            let title = NSAttributedString(string: string, attributes: [.font : timeFont,
                                                                        .foregroundColor: UIColor.lightGray])
            let makeTimeLayout = TextNode.asyncLayout(self.timeNode)
            let (_, apply) = makeTimeLayout(TextNodeLayoutArguments(attributedString: title, backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: titleSize, alignment: .natural, lineSpacing: 0, cutout: nil, insets: .zero))
            let _ = apply()
        })
    }
    
    // MARK: actions
    @objc func playPause(_ sender: Any) {
        interaction.switchPlayingState()
    }
    
    @objc func stop(_ sender: Any) {
        interaction.stop()
    }
}

extension Int {
    var seconds: TimeInterval {
        return TimeInterval(self)
    }
    
    var minutes: TimeInterval {
        return seconds * 60
    }
    
    var hours: TimeInterval {
        return minutes * 60
    }
}
