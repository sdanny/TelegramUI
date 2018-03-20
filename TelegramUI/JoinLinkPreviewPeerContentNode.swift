import Foundation
import AsyncDisplayKit
import Display
import Postbox
import TelegramCore

private let avatarFont: UIFont = UIFont(name: "ArialRoundedMTBold", size: 26.0)!

final class JoinLinkPreviewPeerContentNode: ASDisplayNode, ShareContentContainerNode {
    private var contentOffsetUpdated: ((CGFloat, ContainedViewLayoutTransition) -> Void)?
    
    private let avatarNode: AvatarNode
    private let titleNode: ASTextNode
    private let countNode: ASTextNode
    private let peersScrollNode: ASScrollNode
    
    private let peerNodes: [SelectablePeerNode]
    
    init(account: Account, image: TelegramMediaImageRepresentation?, title: String, memberCount: Int32, members: [Peer], theme: PresentationTheme, strings: PresentationStrings) {
        self.avatarNode = AvatarNode(font: avatarFont)
        self.titleNode = ASTextNode()
        self.countNode = ASTextNode()
        self.peersScrollNode = ASScrollNode()
        
        let itemTheme = SelectablePeerNodeTheme(textColor: theme.actionSheet.primaryTextColor, secretTextColor: .green, selectedTextColor: theme.actionSheet.controlAccentColor, checkBackgroundColor: theme.actionSheet.opaqueItemBackgroundColor, checkFillColor: theme.actionSheet.controlAccentColor, checkColor: theme.actionSheet.opaqueItemBackgroundColor)
        
        self.peerNodes = members.map { peer in
            let node = SelectablePeerNode()
            node.setup(account: account, strings: strings, peer: peer, chatPeer: nil)
            node.theme = itemTheme
            return node
        }
        
        super.init()
        
        let peer = TelegramGroup(id: PeerId(namespace: 0, id: 0), title: title, photo: image.flatMap { [$0] } ?? [], participantCount: Int(memberCount), role: .member, membership: .Left, flags: [], migrationReference: nil, creationDate: 0, version: 0)
        
        self.addSubnode(self.avatarNode)
        self.avatarNode.setPeer(account: account, peer: peer)
        
        self.addSubnode(self.titleNode)
        self.titleNode.attributedText = NSAttributedString(string: title, font: Font.semibold(16.0), textColor: theme.actionSheet.primaryTextColor)
        
        self.addSubnode(self.countNode)
        let membersString: String
        if !members.isEmpty {
            membersString = strings.Invitation_Members(memberCount)
        } else {
            membersString = strings.Conversation_StatusMembers(memberCount)
        }
        self.countNode.attributedText = NSAttributedString(string: membersString, font: Font.regular(16.0), textColor: theme.actionSheet.secondaryTextColor)
        
        if !self.peerNodes.isEmpty {
            for peerNode in peerNodes {
                self.peersScrollNode.addSubnode(peerNode)
            }
            self.addSubnode(self.peersScrollNode)
        }
    }
    
    func activate() {
    }
    
    func deactivate() {
    }
    
    func setEnsurePeerVisibleOnLayout(_ peerId: PeerId?) {
    }
    
    func setContentOffsetUpdated(_ f: ((CGFloat, ContainedViewLayoutTransition) -> Void)?) {
        self.contentOffsetUpdated = f
    }
    
    func updateLayout(size: CGSize, bottomInset: CGFloat, transition: ContainedViewLayoutTransition) {
        let nodeHeight: CGFloat = self.peerNodes.isEmpty ? 224.0 : 324.0
        
        let verticalOrigin = size.height - nodeHeight
        
        let avatarSize: CGFloat = 75.0
        
        transition.updateFrame(node: self.avatarNode, frame: CGRect(origin: CGPoint(x: floor((size.width - avatarSize) / 2.0), y: verticalOrigin + 22.0), size: CGSize(width: avatarSize, height: avatarSize)))
        
        let titleSize = self.titleNode.measure(size)
        transition.updateFrame(node: self.titleNode, frame: CGRect(origin: CGPoint(x: floor((size.width - titleSize.width) / 2.0), y: verticalOrigin + 22.0 + avatarSize + 15.0), size: titleSize))
        
        let countSize = self.countNode.measure(size)
        transition.updateFrame(node: self.countNode, frame: CGRect(origin: CGPoint(x: floor((size.width - countSize.width) / 2.0), y: verticalOrigin + 22.0 + avatarSize + 15.0 + titleSize.height + 1.0), size: countSize))
        
        let peerSize = CGSize(width: 85.0, height: 95.0)
        let peerInset: CGFloat = 10.0
        
        var peerOffset = peerInset
        for node in self.peerNodes {
            node.frame = CGRect(origin: CGPoint(x: peerOffset, y: 0.0), size: peerSize)
            peerOffset += peerSize.width
        }
        
        self.peersScrollNode.view.contentSize = CGSize(width: CGFloat(self.peerNodes.count) * peerSize.width + peerInset * 2.0, height: peerSize.height)
        transition.updateFrame(node: self.peersScrollNode, frame: CGRect(origin: CGPoint(x: 0.0, y: verticalOrigin + 168.0), size: CGSize(width: size.width, height: peerSize.height)))
        
        self.contentOffsetUpdated?(-size.height + nodeHeight - 64.0, transition)
    }
    
    func updateSelectedPeers() {
    }
}