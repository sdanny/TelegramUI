import Foundation
import Display
import AsyncDisplayKit
import SwiftSignalKit
import Postbox
import TelegramCore

struct ItemListStickerPackItemEditing: Equatable {
    let editable: Bool
    let editing: Bool
    let revealed: Bool
    let reorderable: Bool
    
    static func ==(lhs: ItemListStickerPackItemEditing, rhs: ItemListStickerPackItemEditing) -> Bool {
        if lhs.editable != rhs.editable {
            return false
        }
        if lhs.editing != rhs.editing {
            return false
        }
        if lhs.revealed != rhs.revealed {
            return false
        }
        if lhs.reorderable != rhs.reorderable {
            return false
        }
        return true
    }
}

enum ItemListStickerPackItemControl: Equatable {
    case none
    case installation(installed: Bool)
    case selection
}

final class ItemListStickerPackItem: ListViewItem, ItemListItem {
    let theme: PresentationTheme
    let strings: PresentationStrings
    let account: Account
    let packInfo: StickerPackCollectionInfo
    let itemCount: String
    let topItem: StickerPackItem?
    let unread: Bool
    let control: ItemListStickerPackItemControl
    let editing: ItemListStickerPackItemEditing
    let enabled: Bool
    let sectionId: ItemListSectionId
    let action: (() -> Void)?
    let setPackIdWithRevealedOptions: (ItemCollectionId?, ItemCollectionId?) -> Void
    let addPack: () -> Void
    let removePack: () -> Void
    
    init(theme: PresentationTheme, strings: PresentationStrings, account: Account, packInfo: StickerPackCollectionInfo, itemCount: String, topItem: StickerPackItem?, unread: Bool, control: ItemListStickerPackItemControl, editing: ItemListStickerPackItemEditing, enabled: Bool, sectionId: ItemListSectionId, action: (() -> Void)?, setPackIdWithRevealedOptions: @escaping (ItemCollectionId?, ItemCollectionId?) -> Void, addPack: @escaping () -> Void, removePack: @escaping () -> Void) {
        self.theme = theme
        self.strings = strings
        self.account = account
        self.packInfo = packInfo
        self.itemCount = itemCount
        self.topItem = topItem
        self.unread = unread
        self.control = control
        self.editing = editing
        self.enabled = enabled
        self.sectionId = sectionId
        self.action = action
        self.setPackIdWithRevealedOptions = setPackIdWithRevealedOptions
        self.addPack = addPack
        self.removePack = removePack
    }
    
    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = ItemListStickerPackItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
            
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            
            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply(false) })
                })
            }
        }
    }
    
    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? ItemListStickerPackItemNode {
                let makeLayout = nodeValue.asyncLayout()
                
                var animated = true
                if case .None = animation {
                    animated = false
                }
                
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
                    Queue.mainQueue().async {
                        completion(layout, { _ in
                            apply(animated)
                        })
                    }
                }
            }
        }
    }
    
    var selectable: Bool = true
    
    func selected(listView: ListView){
        listView.clearHighlightAnimated(true)
        self.action?()
    }
}

private let titleFont = Font.bold(15.0)
private let statusFont = Font.regular(14.0)

class ItemListStickerPackItemNode: ItemListRevealOptionsItemNode {
    private let backgroundNode: ASDisplayNode
    private let topStripeNode: ASDisplayNode
    private let bottomStripeNode: ASDisplayNode
    private let highlightedBackgroundNode: ASDisplayNode
    private var disabledOverlayNode: ASDisplayNode?
    
    fileprivate let imageNode: TransformImageNode
    private let unreadNode: ASImageNode
    private let titleNode: TextNode
    private let statusNode: TextNode
    private let installationActionImageNode: ASImageNode
    private let installationActionNode: HighlightableButtonNode
    private let selectionIconNode: ASImageNode
    
    private var layoutParams: (ItemListStickerPackItem, ListViewItemLayoutParams, ItemListNeighbors)?
    
    private var editableControlNode: ItemListEditableControlNode?
    private var reorderControlNode: ItemListEditableReorderControlNode?
    
    private let fetchDisposable = MetaDisposable()
    
    override var canBeSelected: Bool {
        if self.editableControlNode != nil || self.disabledOverlayNode != nil {
            return false
        }
        if let item = self.layoutParams?.0, item.action != nil {
            return super.canBeSelected
        } else {
            return false
        }
    }
    
    init() {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true
        
        self.topStripeNode = ASDisplayNode()
        self.topStripeNode.isLayerBacked = true
        
        self.bottomStripeNode = ASDisplayNode()
        self.bottomStripeNode.isLayerBacked = true
        
        self.imageNode = TransformImageNode()
        self.imageNode.isLayerBacked = !smartInvertColorsEnabled()
        
        self.titleNode = TextNode()
        self.titleNode.isUserInteractionEnabled = false
        self.titleNode.contentMode = .left
        self.titleNode.contentsScale = UIScreen.main.scale
        
        self.statusNode = TextNode()
        self.statusNode.isUserInteractionEnabled = false
        self.statusNode.contentMode = .left
        self.statusNode.contentsScale = UIScreen.main.scale
        
        self.unreadNode = ASImageNode()
        self.unreadNode.isLayerBacked = true
        self.unreadNode.displaysAsynchronously = false
        self.unreadNode.displayWithoutProcessing = true
        
        self.installationActionImageNode = ASImageNode()
        self.installationActionImageNode.displaysAsynchronously = false
        self.installationActionImageNode.displayWithoutProcessing = true
        self.installationActionImageNode.isLayerBacked = true
        self.installationActionNode = HighlightableButtonNode()
        
        self.selectionIconNode = ASImageNode()
        self.selectionIconNode.displaysAsynchronously = false
        self.selectionIconNode.displayWithoutProcessing = true
        self.selectionIconNode.isLayerBacked = true
        
        self.highlightedBackgroundNode = ASDisplayNode()
        self.highlightedBackgroundNode.isLayerBacked = true
        
        super.init(layerBacked: false, dynamicBounce: false, rotated: false, seeThrough: false)
        
        self.addSubnode(self.imageNode)
        self.addSubnode(self.titleNode)
        self.addSubnode(self.statusNode)
        self.addSubnode(self.unreadNode)
        self.addSubnode(self.installationActionImageNode)
        self.addSubnode(self.installationActionNode)
        self.addSubnode(self.selectionIconNode)
        
        self.installationActionNode.addTarget(self, action: #selector(self.installationActionPressed), forControlEvents: .touchUpInside)
        self.installationActionNode.highligthedChanged = { [weak self] highlighted in
            if let strongSelf = self {
                if highlighted {
                    strongSelf.installationActionImageNode.layer.removeAnimation(forKey: "opacity")
                    strongSelf.installationActionImageNode.alpha = 0.4
                } else {
                    strongSelf.installationActionImageNode.alpha = 1.0
                    strongSelf.installationActionImageNode.layer.animateAlpha(from: 0.4, to: 1.0, duration: 0.2)
                }
            }
        }
    }
    
    deinit {
        self.fetchDisposable.dispose()
    }
    
    func asyncLayout() -> (_ item: ItemListStickerPackItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, (Bool) -> Void) {
        let makeImageLayout = self.imageNode.asyncLayout()
        let makeTitleLayout = TextNode.asyncLayout(self.titleNode)
        let makeStatusLayout = TextNode.asyncLayout(self.statusNode)
        let editableControlLayout = ItemListEditableControlNode.asyncLayout(self.editableControlNode)
        let reorderControlLayout = ItemListEditableReorderControlNode.asyncLayout(self.reorderControlNode)
        
        var previousThumbnailItem: TelegramMediaImageRepresentation?
        if let thumbnail = self.layoutParams?.0.packInfo.thumbnail {
            previousThumbnailItem = thumbnail
        } else if let item = self.layoutParams?.0.topItem, let dimensions = item.file.dimensions, let resource = chatMessageStickerResource(file: item.file, small: true) as? TelegramMediaResource {
            previousThumbnailItem = TelegramMediaImageRepresentation(dimensions: dimensions, resource: resource)
        }
        
        var currentDisabledOverlayNode = self.disabledOverlayNode
        
        let currentItem = self.layoutParams?.0
        
        return { item, params, neighbors in
            var titleAttributedString: NSAttributedString?
            var statusAttributedString: NSAttributedString?
            
            var updatedTheme: PresentationTheme?
            
            if currentItem?.theme !== item.theme {
                updatedTheme = item.theme
            }
            
            let packRevealOptions: [ItemListRevealOption]
            if item.editing.editable && item.enabled {
                packRevealOptions = [ItemListRevealOption(key: 0, title: item.strings.Common_Delete, icon: .none, color: item.theme.list.itemDisclosureActions.destructive.fillColor, textColor: item.theme.list.itemDisclosureActions.destructive.foregroundColor)]
            } else {
                packRevealOptions = []
            }
            
            var rightInset: CGFloat = params.rightInset
            
            var installationActionImage: UIImage?
            var checkImage: UIImage?
            switch item.control {
                case .none:
                    break
                case let .installation(installed):
                    rightInset += 50.0
                    if installed {
                        installationActionImage = PresentationResourcesItemList.secondaryCheckIconImage(item.theme)
                    } else {
                        installationActionImage = PresentationResourcesItemList.plusIconImage(item.theme)
                    }
                case .selection:
                    rightInset += 16.0
                    checkImage = PresentationResourcesItemList.checkIconImage(item.theme)
            }
            
            var unreadImage: UIImage?
            if item.unread {
                unreadImage = PresentationResourcesItemList.stickerUnreadDotImage(item.theme)
            }
            
            titleAttributedString = NSAttributedString(string: item.packInfo.title, font: titleFont, textColor: item.theme.list.itemPrimaryTextColor)
            statusAttributedString = NSAttributedString(string: item.itemCount, font: statusFont, textColor: item.theme.list.itemSecondaryTextColor)
            
            let leftInset: CGFloat = 65.0 + params.leftInset
            
            let insets = itemListNeighborsGroupedInsets(neighbors)
            let contentSize = CGSize(width: params.width, height: 59.0)
            let separatorHeight = UIScreenPixel
            
            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)
            let layoutSize = layout.size
            
            var editableControlSizeAndApply: (CGSize, () -> ItemListEditableControlNode)?
            var reorderControlSizeAndApply: (CGSize, (Bool) -> ItemListEditableReorderControlNode)?
            
            var editingOffset: CGFloat = 0.0
            var reorderInset: CGFloat = 0.0
            
            if item.editing.editing {
                let sizeAndApply = editableControlLayout(59.0, item.theme, false)
                editableControlSizeAndApply = sizeAndApply
                editingOffset = sizeAndApply.0.width
                
                if item.editing.reorderable {
                    let sizeAndApply = reorderControlLayout(contentSize.height, item.theme)
                    reorderControlSizeAndApply = sizeAndApply
                    reorderInset = sizeAndApply.0.width
                }
            }
            
            let (titleLayout, titleApply) = makeTitleLayout(TextNodeLayoutArguments(attributedString: titleAttributedString, backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: params.width - leftInset - 8.0 - editingOffset - rightInset - 10.0 - reorderInset, height: CGFloat.greatestFiniteMagnitude), alignment: .natural, cutout: nil, insets: UIEdgeInsets()))
            let (statusLayout, statusApply) = makeStatusLayout(TextNodeLayoutArguments(attributedString: statusAttributedString, backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: params.width - leftInset - 8.0 - editingOffset - rightInset - reorderInset, height: CGFloat.greatestFiniteMagnitude), alignment: .natural, cutout: nil, insets: UIEdgeInsets()))
            
            if !item.enabled {
                if currentDisabledOverlayNode == nil {
                    currentDisabledOverlayNode = ASDisplayNode()
                    currentDisabledOverlayNode?.backgroundColor = item.theme.list.itemBlocksBackgroundColor.withAlphaComponent(0.5)
                }
            } else {
                currentDisabledOverlayNode = nil
            }
            
            var thumbnailItem: TelegramMediaImageRepresentation?
            var resourceReference: MediaResourceReference?
            if let thumbnail = item.packInfo.thumbnail {
                thumbnailItem = thumbnail
                resourceReference = MediaResourceReference.stickerPackThumbnail(stickerPack: .id(id: item.packInfo.id.id, accessHash: item.packInfo.accessHash), resource: thumbnail.resource)
            } else if let item = item.topItem, let dimensions = item.file.dimensions, let resource = chatMessageStickerResource(file: item.file, small: true) as? TelegramMediaResource {
                thumbnailItem = TelegramMediaImageRepresentation(dimensions: dimensions, resource: resource)
                resourceReference = MediaResourceReference.media(media: .standalone(media: item.file), resource: resource)
            }
            
            let fileUpdated = thumbnailItem != previousThumbnailItem
            
            var imageApply: (() -> Void)?
            var imageSize: CGSize = CGSize(width: 34.0, height: 34.0)
            if let thumbnailItem = thumbnailItem {
                let imageBoundingSize = CGSize(width: 34.0, height: 34.0)
                imageSize = thumbnailItem.dimensions.aspectFitted(imageBoundingSize)
                imageApply = makeImageLayout(TransformImageArguments(corners: ImageCorners(), imageSize: imageSize, boundingSize: imageSize, intrinsicInsets: UIEdgeInsets()))
            }
            
            var updatedImageSignal: Signal<(TransformImageArguments) -> DrawingContext?, NoError>?
            var updatedFetchSignal: Signal<FetchResourceSourceType, FetchResourceError>?
            if fileUpdated {
                if let thumbnailItem = thumbnailItem {
                    updatedImageSignal = chatMessageStickerPackThumbnail(postbox: item.account.postbox, representation: thumbnailItem)
                    if let resourceReference = resourceReference {
                        updatedFetchSignal = fetchedMediaResource(postbox: item.account.postbox, reference: resourceReference)
                    }
                } else {
                    updatedImageSignal = .single({ _ in return nil })
                    updatedFetchSignal = .complete()
                }
            }
            
            return (layout, { [weak self] animated in
                if let strongSelf = self {
                    strongSelf.layoutParams = (item, params, neighbors)
                    
                    if let _ = updatedTheme {
                        strongSelf.topStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor
                        strongSelf.bottomStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor
                        strongSelf.backgroundNode.backgroundColor = item.theme.list.itemBlocksBackgroundColor
                        strongSelf.highlightedBackgroundNode.backgroundColor = item.theme.list.itemHighlightedBackgroundColor
                    }
                    
                    let revealOffset = strongSelf.revealOffset
                    
                    let transition: ContainedViewLayoutTransition
                    if animated {
                        transition = ContainedViewLayoutTransition.animated(duration: 0.4, curve: .spring)
                    } else {
                        transition = .immediate
                    }
                    
                    if let currentDisabledOverlayNode = currentDisabledOverlayNode {
                        if currentDisabledOverlayNode != strongSelf.disabledOverlayNode {
                            strongSelf.disabledOverlayNode = currentDisabledOverlayNode
                            strongSelf.addSubnode(currentDisabledOverlayNode)
                            currentDisabledOverlayNode.alpha = 0.0
                            transition.updateAlpha(node: currentDisabledOverlayNode, alpha: 1.0)
                            currentDisabledOverlayNode.frame = CGRect(origin: CGPoint(), size: CGSize(width: layout.contentSize.width, height: layout.contentSize.height - separatorHeight))
                        } else {
                            transition.updateFrame(node: currentDisabledOverlayNode, frame: CGRect(origin: CGPoint(), size: CGSize(width: layout.contentSize.width, height: layout.contentSize.height - separatorHeight)))
                        }
                    } else if let disabledOverlayNode = strongSelf.disabledOverlayNode {
                        transition.updateAlpha(node: disabledOverlayNode, alpha: 0.0, completion: { [weak disabledOverlayNode] _ in
                            disabledOverlayNode?.removeFromSupernode()
                        })
                        strongSelf.disabledOverlayNode = nil
                    }
                    
                    if let editableControlSizeAndApply = editableControlSizeAndApply {
                        if strongSelf.editableControlNode == nil {
                            let editableControlNode = editableControlSizeAndApply.1()
                            editableControlNode.tapped = {
                                if let strongSelf = self {
                                    strongSelf.setRevealOptionsOpened(true, animated: true)
                                    strongSelf.revealOptionsInteractivelyOpened()
                                }
                            }
                            strongSelf.editableControlNode = editableControlNode
                            strongSelf.insertSubnode(editableControlNode, aboveSubnode: strongSelf.imageNode)
                            let editableControlFrame = CGRect(origin: CGPoint(x: params.leftInset + revealOffset, y: 0.0), size: editableControlSizeAndApply.0)
                            editableControlNode.frame = editableControlFrame
                            transition.animatePosition(node: editableControlNode, from: CGPoint(x: -editableControlFrame.size.width / 2.0, y: editableControlFrame.midY))
                            editableControlNode.alpha = 0.0
                            transition.updateAlpha(node: editableControlNode, alpha: 1.0)
                        }
                        strongSelf.editableControlNode?.isHidden = !item.editing.editable
                    } else if let editableControlNode = strongSelf.editableControlNode {
                        var editableControlFrame = editableControlNode.frame
                        editableControlFrame.origin.x = -editableControlFrame.size.width
                        strongSelf.editableControlNode = nil
                        transition.updateAlpha(node: editableControlNode, alpha: 0.0)
                        transition.updateFrame(node: editableControlNode, frame: editableControlFrame, completion: { [weak editableControlNode] _ in
                            editableControlNode?.removeFromSupernode()
                        })
                    }
                    
                    if let reorderControlSizeAndApply = reorderControlSizeAndApply {
                        if strongSelf.reorderControlNode == nil {
                            let reorderControlNode = reorderControlSizeAndApply.1(false)
                            strongSelf.reorderControlNode = reorderControlNode
                            strongSelf.addSubnode(reorderControlNode)
                            let reorderControlFrame = CGRect(origin: CGPoint(x: params.width + revealOffset - params.rightInset - reorderControlSizeAndApply.0.width, y: 0.0), size: reorderControlSizeAndApply.0)
                            reorderControlNode.frame = reorderControlFrame
                            reorderControlNode.alpha = 0.0
                            transition.updateAlpha(node: reorderControlNode, alpha: 1.0)
                        }
                    } else if let reorderControlNode = strongSelf.reorderControlNode {
                        strongSelf.reorderControlNode = nil
                        transition.updateAlpha(node: reorderControlNode, alpha: 0.0, completion: { [weak reorderControlNode] _ in
                            reorderControlNode?.removeFromSupernode()
                        })
                    }
                    
                    imageApply?()
                    
                    let _ = titleApply()
                    let _ = statusApply()
                    
                    let installationActionFrame = CGRect(origin: CGPoint(x: params.width - params.rightInset - 50.0, y: 0.0), size: CGSize(width: 50.0, height: layout.contentSize.height))
                    strongSelf.installationActionNode.frame = installationActionFrame
                    
                    switch item.control {
                        case .none:
                            strongSelf.installationActionNode.isHidden = true
                            strongSelf.installationActionImageNode.isHidden = true
                            strongSelf.selectionIconNode.isHidden = true
                        case let .installation(installed):
                            strongSelf.installationActionImageNode.isHidden = false
                            strongSelf.installationActionNode.isHidden = false
                            strongSelf.selectionIconNode.isHidden = true
                            strongSelf.installationActionNode.isUserInteractionEnabled = !installed
                            if let image = installationActionImage {
                                let imageSize = image.size
                                strongSelf.installationActionImageNode.image = image
                                strongSelf.installationActionImageNode.frame = CGRect(origin: CGPoint(x: installationActionFrame.minX + floor((installationActionFrame.size.width - imageSize.width) / 2.0), y: installationActionFrame.minY + floor((installationActionFrame.size.height - imageSize.height) / 2.0)), size: imageSize)
                            }
                        case .selection:
                            strongSelf.installationActionNode.isHidden = true
                            strongSelf.installationActionImageNode.isHidden = true
                            strongSelf.selectionIconNode.isHidden = false
                            if let image = checkImage {
                                strongSelf.selectionIconNode.image = image
                                strongSelf.selectionIconNode.frame = CGRect(origin: CGPoint(x: params.width - params.rightInset - image.size.width - floor((44.0 - image.size.width) / 2.0), y: floor((contentSize.height - image.size.height) / 2.0)), size: image.size)
                            }
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
                    switch neighbors.top {
                        case .sameSection(false):
                            strongSelf.topStripeNode.isHidden = true
                        default:
                            strongSelf.topStripeNode.isHidden = false
                    }
                    let bottomStripeInset: CGFloat
                    let bottomStripeOffset: CGFloat
                    switch neighbors.bottom {
                        case .sameSection(false):
                            bottomStripeInset = leftInset + editingOffset
                            bottomStripeOffset = -separatorHeight
                        default:
                            bottomStripeInset = 0.0
                            bottomStripeOffset = 0.0
                    }
                    strongSelf.backgroundNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: contentSize.height + min(insets.top, separatorHeight) + min(insets.bottom, separatorHeight)))
                    transition.updateFrame(node: strongSelf.topStripeNode, frame: CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: layoutSize.width, height: separatorHeight)))
                    transition.updateFrame(node: strongSelf.bottomStripeNode, frame: CGRect(origin: CGPoint(x: bottomStripeInset, y: contentSize.height + bottomStripeOffset), size: CGSize(width: layoutSize.width - bottomStripeInset, height: separatorHeight)))
                    
                    if let unreadImage = unreadImage {
                        strongSelf.unreadNode.image = unreadImage
                        strongSelf.unreadNode.isHidden = false
                        strongSelf.unreadNode.frame = CGRect(origin: CGPoint(x: leftInset, y: 16.0), size: unreadImage.size)
                    } else {
                        strongSelf.unreadNode.isHidden = true
                    }
                    
                    transition.updateFrame(node: strongSelf.titleNode, frame: CGRect(origin: CGPoint(x: (strongSelf.unreadNode.isHidden ? 0.0 : 10.0) + leftInset + revealOffset + editingOffset, y: 11.0), size: titleLayout.size))
                    transition.updateFrame(node: strongSelf.statusNode, frame: CGRect(origin: CGPoint(x: leftInset + revealOffset + editingOffset, y: 32.0), size: statusLayout.size))
                    
                    let boundingSize = CGSize(width: 34.0, height: 34.0)
                    transition.updateFrame(node: strongSelf.imageNode, frame: CGRect(origin: CGPoint(x: params.leftInset + revealOffset + editingOffset + 15.0 + floor((boundingSize.width - imageSize.width) / 2.0), y: 11.0 + floor((boundingSize.height - imageSize.height) / 2.0)), size: imageSize))
                    
                    if let updatedImageSignal = updatedImageSignal {
                        strongSelf.imageNode.setSignal(updatedImageSignal)
                    }
                    
                    strongSelf.highlightedBackgroundNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -UIScreenPixel), size: CGSize(width: params.width, height: 59.0 + UIScreenPixel + UIScreenPixel))
                    
                    strongSelf.updateLayout(size: layout.contentSize, leftInset: params.leftInset, rightInset: params.rightInset)
                    
                    strongSelf.setRevealOptions((left: [], right: packRevealOptions))
                    strongSelf.setRevealOptionsOpened(item.editing.revealed, animated: animated)
                    
                    if let updatedFetchSignal = updatedFetchSignal {
                        strongSelf.fetchDisposable.set(updatedFetchSignal.start())
                    }
                }
            })
        }
    }
    
    override func setHighlighted(_ highlighted: Bool, at point: CGPoint, animated: Bool) {
        super.setHighlighted(highlighted, at: point, animated: animated)
        
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
    
    override func animateInsertion(_ currentTimestamp: Double, duration: Double, short: Bool) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.4)
    }
    
    override func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false)
    }
    
    override func updateRevealOffset(offset: CGFloat, transition: ContainedViewLayoutTransition) {
        super.updateRevealOffset(offset: offset, transition: transition)
        
        guard let params = self.layoutParams?.1 else {
            return
        }
        
        let leftInset: CGFloat = 65.0 + params.leftInset
        
        let editingOffset: CGFloat
        if let editableControlNode = self.editableControlNode {
            editingOffset = editableControlNode.bounds.size.width
            var editableControlFrame = editableControlNode.frame
            editableControlFrame.origin.x = params.leftInset + offset
            transition.updateFrame(node: editableControlNode, frame: editableControlFrame)
        } else {
            editingOffset = 0.0
        }
        
        transition.updateFrame(node: self.titleNode, frame: CGRect(origin: CGPoint(x: leftInset + revealOffset + editingOffset, y: self.titleNode.frame.minY), size: self.titleNode.bounds.size))
        transition.updateFrame(node: self.statusNode, frame: CGRect(origin: CGPoint(x: leftInset + revealOffset + editingOffset, y: self.statusNode.frame.minY), size: self.statusNode.bounds.size))
        
        let boundingSize = CGSize(width: 34.0, height: 34.0)
        
        transition.updateFrame(node: self.imageNode, frame: CGRect(origin: CGPoint(x: params.leftInset + revealOffset + editingOffset + 15.0 + floor((boundingSize.width - self.imageNode.frame.size.width) / 2.0), y: self.imageNode.frame.minY), size: self.imageNode.frame.size))
    }
    
    override func revealOptionsInteractivelyOpened() {
        if let (item, _, _) = self.layoutParams {
            item.setPackIdWithRevealedOptions(item.packInfo.id, nil)
        }
    }
    
    override func revealOptionsInteractivelyClosed() {
        if let (item, _, _) = self.layoutParams {
            item.setPackIdWithRevealedOptions(nil, item.packInfo.id)
        }
    }
    
    override func revealOptionSelected(_ option: ItemListRevealOption, animated: Bool) {
        self.setRevealOptionsOpened(false, animated: true)
        self.revealOptionsInteractivelyClosed()
        
        if let (item, _, _) = self.layoutParams {
            item.removePack()
        }
    }
    
    @objc func installationActionPressed() {
        if let (item, _, _) = self.layoutParams {
            item.addPack()
        }
    }
    
    override func isReorderable(at point: CGPoint) -> Bool {
        if let reorderControlNode = self.reorderControlNode, reorderControlNode.frame.contains(point), !self.isDisplayingRevealedOptions {
            return true
        }
        return false
    }
}
