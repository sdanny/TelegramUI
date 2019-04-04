import Foundation
import AsyncDisplayKit
import Display
import TelegramCore
import Postbox

public class ActionSheetPeerItem: ActionSheetItem {
    public let account: Account
    public let peer: Peer
    public let theme: PresentationTheme
    public let title: String
    public let isSelected: Bool
    public let strings: PresentationStrings
    public let action: () -> Void
    
    public init(account: Account, peer: Peer, title: String, isSelected: Bool, strings: PresentationStrings, theme: PresentationTheme, action: @escaping () -> Void) {
        self.account = account
        self.peer = peer
        self.title = title
        self.isSelected = isSelected
        self.strings = strings
        self.theme = theme
        self.action = action
    }
    
    public func node(theme: ActionSheetControllerTheme) -> ActionSheetItemNode {
        let node = ActionSheetPeerItemNode(theme: theme)
        node.setItem(self)
        return node
    }
    
    public func updateNode(_ node: ActionSheetItemNode) {
        guard let node = node as? ActionSheetPeerItemNode else {
            assertionFailure()
            return
        }
        
        node.setItem(self)
    }
}

private let avatarFont: UIFont = UIFont(name: ".SFCompactRounded-Semibold", size: 15.0)!

public class ActionSheetPeerItemNode: ActionSheetItemNode {
    private let theme: ActionSheetControllerTheme
    
    public static let defaultFont: UIFont = Font.regular(20.0)
    
    private var item: ActionSheetPeerItem?
    
    private let button: HighlightTrackingButton
    private let avatarNode: AvatarNode
    private let label: ImmediateTextNode
    private let checkNode: ASImageNode
    
    override public init(theme: ActionSheetControllerTheme) {
        self.theme = theme
        
        self.button = HighlightTrackingButton()
        
        self.avatarNode = AvatarNode(font: avatarFont)
        self.avatarNode.isLayerBacked = !smartInvertColorsEnabled()
        
        self.label = ImmediateTextNode()
        self.label.isUserInteractionEnabled = false
        self.label.displaysAsynchronously = false
        self.label.maximumNumberOfLines = 1
        
        self.checkNode = ASImageNode()
        self.checkNode.displaysAsynchronously = false
        self.checkNode.displayWithoutProcessing = true
        self.checkNode.image = generateItemListCheckIcon(color: theme.primaryTextColor)
        
        super.init(theme: theme)
        
        self.view.addSubview(self.button)
        self.addSubnode(self.avatarNode)
        self.addSubnode(self.label)
        self.addSubnode(self.checkNode)
        
        self.button.highligthedChanged = { [weak self] highlighted in
            if let strongSelf = self {
                if highlighted {
                    strongSelf.backgroundNode.backgroundColor = strongSelf.theme.itemHighlightedBackgroundColor
                } else {
                    UIView.animate(withDuration: 0.3, animations: {
                        strongSelf.backgroundNode.backgroundColor = strongSelf.theme.itemBackgroundColor
                    })
                }
            }
        }
        
        self.button.addTarget(self, action: #selector(self.buttonPressed), for: .touchUpInside)
    }
    
    func setItem(_ item: ActionSheetPeerItem) {
        self.item = item
        
        let textColor: UIColor = self.theme.primaryTextColor
        self.label.attributedText = NSAttributedString(string: item.title, font: ActionSheetButtonNode.defaultFont, textColor: textColor)
        
        self.avatarNode.setPeer(account: item.account, theme: item.theme, peer: item.peer)
        
        self.checkNode.isHidden = !item.isSelected
        
        self.setNeedsLayout()
    }
    
    public override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        return CGSize(width: constrainedSize.width, height: 57.0)
    }
    
    public override func layout() {
        super.layout()
        
        let size = self.bounds.size
        
        self.button.frame = CGRect(origin: CGPoint(), size: size)
        
        let avatarInset: CGFloat = 42.0
        let avatarSize: CGFloat = 32.0
        
        self.avatarNode.frame = CGRect(origin: CGPoint(x: 16.0, y: floor((size.height - avatarSize) / 2.0)), size: CGSize(width: avatarSize, height: avatarSize))
        
        let labelSize = self.label.updateLayout(CGSize(width: max(1.0, size.width - avatarInset - 16.0 - 16.0 - 30.0), height: size.height))
        self.label.frame = CGRect(origin: CGPoint(x: 16.0 + avatarInset, y: floorToScreenPixels((size.height - labelSize.height) / 2.0)), size: labelSize)
        
        if let image = self.checkNode.image {
            self.checkNode.frame = CGRect(origin: CGPoint(x: size.width - image.size.width - 16.0, y: floor((size.height - image.size.height) / 2.0)), size: image.size)
        }
    }
    
    @objc func buttonPressed() {
        if let item = self.item {
            item.action()
        }
    }
}

