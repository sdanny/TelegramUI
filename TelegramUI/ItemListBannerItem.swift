//
//  ItemListBanner.swift
//  TelegramUI
//
//  Created by Daniyar Salakhutdinov on 08/03/2019.
//  Copyright © 2019 Telegram. All rights reserved.
//

import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit

class ItemListBannerItem: ListViewItem, ItemListItem {

    let sectionId: ItemListSectionId
    let action: () -> Void
    
    let selectable = true
    
    init(sectionId: ItemListSectionId, action: @escaping () -> Void) {
        self.sectionId = sectionId
        self.action = action
    }
    
    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = ItemListBannerItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
            
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
        guard let nodeValue = node() as? ItemListBannerItemNode else { return }
        let makeLayout = nodeValue.asyncLayout()
        
        async {
            let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
            Queue.mainQueue().async {
                completion(layout, { _ in
                    apply()
                })
            }
        }
    }
    
    func selected(listView: ListView){
        listView.clearHighlightAnimated(true)
        self.action()
    }
}

class ItemListBannerItemNode: ListViewItemNode, ItemListItemNode {
    var tag: ItemListItemTag?
    
    private var item: ItemListBannerItem?
    
    private let titleNode: TextNode
    private let descriptionNode: TextNode
    private let actionNode: TextNode
    private let imageNode: ImageNode
    private let bubbleNode: ASDisplayNode
    
    init() {
        let scale = UIScreen.main.scale
        
        titleNode = TextNode()
        titleNode.isUserInteractionEnabled = false
        titleNode.contentMode = .center
        titleNode.contentsScale = scale
        
        descriptionNode = TextNode()
        descriptionNode.isUserInteractionEnabled = false
        descriptionNode.contentMode = .center
        descriptionNode.contentsScale = scale
        
        bubbleNode = ASDisplayNode()
        bubbleNode.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        
        actionNode = TextNode()
        actionNode.isUserInteractionEnabled = false
        actionNode.contentMode = .center
        actionNode.contentsScale = scale
        
        imageNode = ImageNode(enableHasImage: true)
        imageNode.contentMode = .scaleAspectFit
        
        super.init(layerBacked: false, dynamicBounce: false)
        
        addSubnode(imageNode)
        addSubnode(titleNode)
        addSubnode(descriptionNode)
        addSubnode(bubbleNode)
        addSubnode(actionNode)
    }
    
    func asyncLayout() -> (_ item: ItemListBannerItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        
        let layoutTitleNode = TextNode.asyncLayout(titleNode)
        let layoutDescriptionNode = TextNode.asyncLayout(descriptionNode)
        let layoutActionNode = TextNode.asyncLayout(actionNode)
        
        let image = UIImage(bundleImageName: "Settings/banner")!
        let imageSize = image.size
        imageNode.setSignal(.single(image))
        
        return { item, params, neighbors in
            let leftInset: CGFloat = 16.0
            let verticalInset: CGFloat = 16.0
            
            let title = NSLocalizedString("Settings.Recording_title", comment: "Telephone call recording!")
            let description = NSLocalizedString("Settings.Recording_description", comment: "Try it for free!")
            let titleText = NSAttributedString(string: title, attributes: [.foregroundColor : UIColor.black, .font : Font.semibold(16)])
            let descriptionText = NSAttributedString(string: description, attributes: [.foregroundColor : UIColor.lightGray, .font : Font.regular(16)])
            
            let actionString = NSLocalizedString("Settings.Recording_action", comment: "Try for free")
            let actionText = NSAttributedString(string: actionString, attributes: [.foregroundColor : UIColor.white, .font : Font.semibold(14)])
            
            let (titleLayout, titleApply) = layoutTitleNode(TextNodeLayoutArguments(attributedString: titleText, backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: params.width - params.rightInset - leftInset * 2, height: CGFloat.greatestFiniteMagnitude), alignment: .natural, cutout: nil, insets: UIEdgeInsets()))
            let (descriptionLayout, descriptionApply) = layoutDescriptionNode(TextNodeLayoutArguments(attributedString: descriptionText, backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: params.width - params.rightInset - leftInset * 2, height: CGFloat.greatestFiniteMagnitude), alignment: .natural, cutout: nil, insets: UIEdgeInsets()))
            let (actionLayout, actionApply) = layoutActionNode(TextNodeLayoutArguments(attributedString: actionText, backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: params.width - params.rightInset, height: CGFloat.greatestFiniteMagnitude), alignment: .natural, cutout: nil, insets: UIEdgeInsets()))
            
            let contentSize = CGSize(width: params.width, height: imageSize.height)
            let insets = itemListNeighborsGroupedInsets(neighbors)
            
            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)
            
            return (layout, { [weak self] in
                guard let self = self else { return }
                self.item = item
                
                let _ = titleApply()
                let _ = descriptionApply()
                let _ = actionApply()
                
                self.titleNode.frame = CGRect(origin: CGPoint(x: (contentSize.width - titleLayout.size.width) / 2, y: verticalInset), size: titleLayout.size)
                self.descriptionNode.frame = CGRect(origin: CGPoint(x: (contentSize.width - descriptionLayout.size.width) / 2, y: verticalInset + titleLayout.size.height), size: descriptionLayout.size)
                let actionRect = CGRect(origin: CGPoint(x: (contentSize.width - actionLayout.size.width) / 2, y: imageSize.height - 48), size: actionLayout.size)
                self.actionNode.frame = actionRect
                self.bubbleNode.frame = actionRect.insetBy(dx: -6, dy: -4)
                self.bubbleNode.layer.cornerRadius = self.bubbleNode.bounds.height / 2
                self.imageNode.frame = CGRect(origin: .zero, size: CGSize(width: contentSize.width, height: imageSize.height))
            })
        }
    }
}
