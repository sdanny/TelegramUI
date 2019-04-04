import Foundation
import Display
import AsyncDisplayKit
import SwiftSignalKit

public enum ContactListActionItemInlineIconPosition {
    case left
    case right
}

public enum ContactListActionItemHighlight {
    case cell
    case alpha
}

public enum ContactListActionItemIcon : Equatable {
    case none
    case generic(UIImage)
    case inline(UIImage, ContactListActionItemInlineIconPosition)
    
    var image: UIImage? {
        switch self {
            case .none:
                return nil
            case let .generic(image):
                return image
            case let .inline(image, _):
                return image
        }
    }
    
    public static func ==(lhs: ContactListActionItemIcon, rhs: ContactListActionItemIcon) -> Bool {
        switch lhs {
            case .none:
                if case .none = rhs {
                    return true
                } else {
                    return false
                }
            case let .generic(image):
                if case .generic(image) = rhs {
                    return true
                } else {
                    return false
                }
            case let .inline(image, position):
                if case .inline(image, position) = rhs {
                    return true
                } else {
                    return false
                }
        }
    }
}

class ContactListActionItem: ListViewItem {
    let theme: PresentationTheme
    let title: String
    let icon: ContactListActionItemIcon
    let highlight: ContactListActionItemHighlight
    let action: () -> Void
    let header: ListViewItemHeader?
    
    init(theme: PresentationTheme, title: String, icon: ContactListActionItemIcon, highlight: ContactListActionItemHighlight = .cell, header: ListViewItemHeader?, action: @escaping () -> Void) {
        self.theme = theme
        self.title = title
        self.icon = icon
        self.highlight = highlight
        self.header = header
        self.action = action
    }
    
    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = ContactListActionItemNode()
            let (_, last, firstWithHeader) = ContactListActionItem.mergeType(item: self, previousItem: previousItem, nextItem: nextItem)
            let (layout, apply) = node.asyncLayout()(self, params, firstWithHeader, last)
            
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            
            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply() })
                })
            }
        }
    }
    
    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? ContactListActionItemNode {
                let makeLayout = nodeValue.asyncLayout()
                
                async {
                    let (_, last, firstWithHeader) = ContactListActionItem.mergeType(item: self, previousItem: previousItem, nextItem: nextItem)
                    let (layout, apply) = makeLayout(self, params, firstWithHeader, last)
                    Queue.mainQueue().async {
                        completion(layout, { _ in
                            apply()
                        })
                    }
                }
            }
        }
    }
    
    var selectable: Bool = true
    
    func selected(listView: ListView){
        listView.clearHighlightAnimated(true)
        self.action()
    }
    
    static func mergeType(item: ContactListActionItem, previousItem: ListViewItem?, nextItem: ListViewItem?) -> (first: Bool, last: Bool, firstWithHeader: Bool) {
        var first = false
        var last = false
        var firstWithHeader = false
        if let previousItem = previousItem {
            if let header = item.header {
                if let previousItem = previousItem as? ContactsPeerItem {
                    firstWithHeader = header.id != previousItem.header?.id
                } else if let previousItem = previousItem as? ContactListActionItem {
                    firstWithHeader = header.id != previousItem.header?.id
                } else {
                    firstWithHeader = true
                }
            }
        } else {
            first = true
            firstWithHeader = item.header != nil
        }
        if let nextItem = nextItem {
            if let nextItem = nextItem as? ContactsPeerItem {
                last = item.header?.id != nextItem.header?.id
            } else if let nextItem = nextItem as? ContactListActionItem {
                last = item.header?.id != nextItem.header?.id
            } else {
                last = true
            }
        } else {
            last = true
        }
        return (first, last, firstWithHeader)
    }
}

private let titleFont = Font.regular(17.0)

class ContactListActionItemNode: ListViewItemNode {
    private let backgroundNode: ASDisplayNode
    private let topStripeNode: ASDisplayNode
    private let bottomStripeNode: ASDisplayNode
    private let highlightedBackgroundNode: ASDisplayNode
    
    private let iconNode: ASImageNode
    private let titleNode: TextNode
    
    private let activateArea: AccessibilityAreaNode
    
    private var theme: PresentationTheme?
    
    private var item: ContactListActionItem?
    
    init() {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true
        self.backgroundNode.backgroundColor = .white
        
        self.topStripeNode = ASDisplayNode()
        self.topStripeNode.isLayerBacked = true
        
        self.bottomStripeNode = ASDisplayNode()
        self.bottomStripeNode.isLayerBacked = true
        
        self.titleNode = TextNode()
        self.titleNode.isUserInteractionEnabled = false
        self.titleNode.contentMode = .left
        self.titleNode.contentsScale = UIScreen.main.scale
        
        self.iconNode = ASImageNode()
        self.iconNode.isLayerBacked = true
        self.iconNode.displayWithoutProcessing = true
        self.iconNode.displaysAsynchronously = false
        
        self.highlightedBackgroundNode = ASDisplayNode()
        self.highlightedBackgroundNode.isLayerBacked = true
        
        self.activateArea = AccessibilityAreaNode()
        
        super.init(layerBacked: false, dynamicBounce: false)
        
        self.addSubnode(self.iconNode)
        self.addSubnode(self.titleNode)
        self.addSubnode(self.activateArea)
        
        self.activateArea.activate = { [weak self] in
            self?.item?.action()
            return true
        }
    }
    
    func asyncLayout() -> (_ item: ContactListActionItem, _ params: ListViewItemLayoutParams, _ firstWithHeader: Bool, _ last: Bool) -> (ListViewItemNodeLayout, () -> Void) {
        let makeTitleLayout = TextNode.asyncLayout(self.titleNode)
        let currentTheme = self.theme
        
        return { item, params, firstWithHeader, last in
            var updatedTheme: PresentationTheme?
            
            if currentTheme !== item.theme {
                updatedTheme = item.theme
            }
            
            var leftInset: CGFloat = 16.0 + params.leftInset
            if case .generic = item.icon {
                leftInset += 49.0
            }
            
            let (titleLayout, titleApply) = makeTitleLayout(TextNodeLayoutArguments(attributedString: NSAttributedString(string: item.title, font: titleFont, textColor: item.theme.list.itemAccentColor), backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: params.width - 10.0 - leftInset - params.rightInset, height: CGFloat.greatestFiniteMagnitude), alignment: .natural, cutout: nil, insets: UIEdgeInsets()))
            
            let contentSize = CGSize(width: params.width, height: 50.0)
            let insets = UIEdgeInsets(top: firstWithHeader ? 29.0 : 0.0, left: 0.0, bottom: 0.0, right: 0.0)
            let separatorHeight = UIScreenPixel
            
            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)
            
            return (layout, { [weak self] in
                if let strongSelf = self {
                    strongSelf.item = item
                    strongSelf.theme = item.theme
                    
                    strongSelf.activateArea.accessibilityLabel = item.title
                    strongSelf.activateArea.frame = CGRect(origin: CGPoint(x: params.leftInset, y: 0.0), size: CGSize(width: layout.contentSize.width - params.leftInset - params.rightInset, height: layout.contentSize.height))
                    
                    if let _ = updatedTheme {
                        strongSelf.topStripeNode.backgroundColor = item.theme.list.itemPlainSeparatorColor
                        strongSelf.bottomStripeNode.backgroundColor = item.theme.list.itemPlainSeparatorColor
                        strongSelf.backgroundNode.backgroundColor = item.theme.list.plainBackgroundColor
                        strongSelf.highlightedBackgroundNode.backgroundColor = item.theme.list.itemHighlightedBackgroundColor
                        
                        strongSelf.iconNode.image = generateTintedImage(image: item.icon.image, color: item.theme.list.itemAccentColor)
                    }
                    
                    let _ = titleApply()

                    var titleOffset = leftInset
                    var hideBottomStripe: Bool = last
                    if let image = item.icon.image {
                        var iconFrame: CGRect
                        switch item.icon {
                            case let .inline(_, position):
                                hideBottomStripe = true
                                let iconSpacing: CGFloat = 4.0
                                let totalWidth: CGFloat = titleLayout.size.width + image.size.width + iconSpacing
                                switch position {
                                    case .left:
                                        iconFrame = CGRect(origin: CGPoint(x: params.leftInset + floor((contentSize.width - params.leftInset - params.rightInset - totalWidth) / 2.0), y: floor((contentSize.height - image.size.height) / 2.0)), size: image.size)
                                        titleOffset = iconFrame.minX + iconSpacing
                                    case .right:
                                        iconFrame = CGRect(origin: CGPoint(x: params.leftInset + floor((contentSize.width - params.leftInset - params.rightInset - totalWidth) / 2.0) + totalWidth - image.size.width, y: floor((contentSize.height - image.size.height) / 2.0)), size: image.size)
                                        titleOffset = iconFrame.maxX - totalWidth
                                }
                            default:
                                iconFrame = CGRect(origin: CGPoint(x: params.leftInset + floor((leftInset - params.leftInset - image.size.width) / 2.0), y: floor((contentSize.height - image.size.height) / 2.0)), size: image.size)
                        }
                        strongSelf.iconNode.frame = iconFrame
                    }
                    
                    if strongSelf.backgroundNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.backgroundNode, at: 0)
                    }
                    if strongSelf.topStripeNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.topStripeNode, at: 1)
                    }
                    if strongSelf.bottomStripeNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.bottomStripeNode, at: 2)
                    }
                    
                    strongSelf.topStripeNode.isHidden = true
                    strongSelf.bottomStripeNode.isHidden = hideBottomStripe
                    if !hideBottomStripe {
                        print("")
                    }
                    
                    strongSelf.bottomStripeNode.frame = CGRect(origin: CGPoint(x: leftInset, y: contentSize.height - separatorHeight), size: CGSize(width: params.width - leftInset, height: separatorHeight))
                    
                    strongSelf.titleNode.frame = CGRect(origin: CGPoint(x: titleOffset, y: floor((contentSize.height - titleLayout.size.height) / 2.0)), size: titleLayout.size)
                    
                    strongSelf.highlightedBackgroundNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -UIScreenPixel), size: CGSize(width: params.width, height: 50.0 + UIScreenPixel + UIScreenPixel))
                }
            })
        }
    }
    
    override func setHighlighted(_ highlighted: Bool, at point: CGPoint, animated: Bool) {
        super.setHighlighted(highlighted, at: point, animated: animated)
        
        if let item = self.item, case .alpha = item.highlight {
            if highlighted {
                self.titleNode.alpha = 0.4
                self.iconNode.alpha = 0.4
            } else {
                if animated {
                    self.titleNode.layer.animateAlpha(from: self.titleNode.alpha, to: 1.0, duration: 0.2)
                    self.iconNode.layer.animateAlpha(from: self.iconNode.alpha, to: 1.0, duration: 0.2)
                }
                self.titleNode.alpha = 1.0
                self.iconNode.alpha = 1.0
            }
        } else {
            if highlighted {
                self.highlightedBackgroundNode.alpha = 1.0
                if self.highlightedBackgroundNode.supernode == nil {
                    var anchorNode: ASDisplayNode?
                    if self.bottomStripeNode.supernode != nil {
                        anchorNode = self.bottomStripeNode
                    } else if self.topStripeNode.supernode != nil {
                        anchorNode = self.topStripeNode
                    } else if self.backgroundNode.supernode != nil {
                        anchorNode = self.backgroundNode
                    }
                    if let anchorNode = anchorNode {
                        self.insertSubnode(self.highlightedBackgroundNode, aboveSubnode: anchorNode)
                    } else {
                        self.addSubnode(self.highlightedBackgroundNode)
                    }
                }
            } else {
                if self.highlightedBackgroundNode.supernode != nil {
                    if animated {
                        self.highlightedBackgroundNode.layer.animateAlpha(from: self.highlightedBackgroundNode.alpha, to: 0.0, duration: 0.4, completion: { [weak self] completed in
                            if let strongSelf = self {
                                if completed {
                                    strongSelf.highlightedBackgroundNode.removeFromSupernode()
                                }
                            }
                        })
                        self.highlightedBackgroundNode.alpha = 0.0
                    } else {
                        self.highlightedBackgroundNode.removeFromSupernode()
                    }
                }
            }
        }
    }
    
    override func animateInsertion(_ currentTimestamp: Double, duration: Double, short: Bool) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.4)
    }
    
    override func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false)
    }
    
    override public func header() -> ListViewItemHeader? {
        if let item = self.item {
            return item.header
        } else {
            return nil
        }
    }
}
