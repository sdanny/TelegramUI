import Foundation
import AsyncDisplayKit
import Display
import Postbox
import TelegramCore
import SwiftSignalKit

final class ChatMessageSelectionInputPanelNode: ChatInputPanelNode {
    private let deleteButton: HighlightableButtonNode
    private let reportButton: HighlightableButtonNode
    private let forwardButton: HighlightableButtonNode
    private let shareButton: HighlightableButtonNode
    
    private var validLayout: (width: CGFloat, leftInset: CGFloat, rightInset: CGFloat, maxHeight: CGFloat, metrics: LayoutMetrics)?
    private var presentationInterfaceState: ChatPresentationInterfaceState?
    private var actions: ChatAvailableMessageActions?
    
    private var theme: PresentationTheme
    
    private let canDeleteMessagesDisposable = MetaDisposable()
    
    var selectedMessages = Set<MessageId>() {
        didSet {
            if oldValue != self.selectedMessages {
                self.forwardButton.isEnabled = self.selectedMessages.count != 0
                
                if self.selectedMessages.isEmpty {
                    self.actions = nil
                    if let (width, leftInset, rightInset, maxHeight, metrics) = self.validLayout, let interfaceState = self.presentationInterfaceState {
                        let _ = self.updateLayout(width: width, leftInset: leftInset, rightInset: rightInset, maxHeight: maxHeight, transition: .immediate, interfaceState: interfaceState, metrics: metrics)
                    }
                    self.canDeleteMessagesDisposable.set(nil)
                } else if let context = self.context {
                    self.canDeleteMessagesDisposable.set((chatAvailableMessageActions(postbox: context.account.postbox, accountPeerId: context.account.peerId, messageIds: self.selectedMessages)
                    |> deliverOnMainQueue).start(next: { [weak self] actions in
                        if let strongSelf = self {
                            strongSelf.actions = actions
                            if let (width, leftInset, rightInset, maxHeight, metrics) = strongSelf.validLayout, let interfaceState = strongSelf.presentationInterfaceState {
                                let _ = strongSelf.updateLayout(width: width, leftInset: leftInset, rightInset: rightInset, maxHeight: maxHeight, transition: .immediate, interfaceState: interfaceState, metrics: metrics)
                            }
                        }
                    }))
                }
            }
        }
    }
    
    init(theme: PresentationTheme) {
        self.theme = theme
        
        self.deleteButton = HighlightableButtonNode()
        self.deleteButton.isEnabled = false
        self.deleteButton.isAccessibilityElement = true
        self.deleteButton.accessibilityLabel = "Delete"
        
        self.reportButton = HighlightableButtonNode()
        self.reportButton.isEnabled = false
        self.reportButton.isAccessibilityElement = true
        self.reportButton.accessibilityLabel = "Report"
        
        self.forwardButton = HighlightableButtonNode()
        self.forwardButton.isAccessibilityElement = true
        self.forwardButton.accessibilityLabel = "Forward"
        
        self.shareButton = HighlightableButtonNode()
        self.shareButton.isEnabled = false
        self.shareButton.isAccessibilityElement = true
        self.shareButton.accessibilityLabel = "Share"
        
        self.deleteButton.setImage(generateTintedImage(image: UIImage(bundleImageName: "Chat/Input/Accessory Panels/MessageSelectionThrash"), color: theme.chat.inputPanel.panelControlAccentColor), for: [.normal])
        self.deleteButton.setImage(generateTintedImage(image: UIImage(bundleImageName: "Chat/Input/Accessory Panels/MessageSelectionThrash"), color: theme.chat.inputPanel.panelControlDisabledColor), for: [.disabled])
        self.reportButton.setImage(generateTintedImage(image: UIImage(bundleImageName: "Chat/Input/Accessory Panels/MessageSelectionReport"), color: theme.chat.inputPanel.panelControlAccentColor), for: [.normal])
        self.reportButton.setImage(generateTintedImage(image: UIImage(bundleImageName: "Chat/Input/Accessory Panels/MessageSelectionReport"), color: theme.chat.inputPanel.panelControlDisabledColor), for: [.disabled])
        self.forwardButton.setImage(generateTintedImage(image: UIImage(bundleImageName: "Chat/Input/Accessory Panels/MessageSelectionForward"), color: theme.chat.inputPanel.panelControlAccentColor), for: [.normal])
        self.forwardButton.setImage(generateTintedImage(image: UIImage(bundleImageName: "Chat/Input/Accessory Panels/MessageSelectionForward"), color: theme.chat.inputPanel.panelControlDisabledColor), for: [.disabled])
        self.shareButton.setImage(generateTintedImage(image: UIImage(bundleImageName: "Chat List/NavigationShare"), color: theme.chat.inputPanel.panelControlAccentColor), for: [.normal])
        self.shareButton.setImage(generateTintedImage(image: UIImage(bundleImageName: "Chat List/NavigationShare"), color: theme.chat.inputPanel.panelControlDisabledColor), for: [.disabled])
        
        super.init()
        
        self.addSubnode(self.deleteButton)
        self.addSubnode(self.reportButton)
        self.addSubnode(self.forwardButton)
        self.addSubnode(self.shareButton)
        
        self.forwardButton.isEnabled = false
        
        self.deleteButton.addTarget(self, action: #selector(self.deleteButtonPressed), forControlEvents: .touchUpInside)
        self.reportButton.addTarget(self, action: #selector(self.reportButtonPressed), forControlEvents: .touchUpInside)
        self.forwardButton.addTarget(self, action: #selector(self.forwardButtonPressed), forControlEvents: .touchUpInside)
        self.shareButton.addTarget(self, action: #selector(self.shareButtonPressed), forControlEvents: .touchUpInside)
    }
    
    deinit {
        self.canDeleteMessagesDisposable.dispose()
    }
    
    func updateTheme(theme: PresentationTheme) {
        if self.theme !== theme {
            self.theme = theme
            
            self.deleteButton.setImage(generateTintedImage(image: UIImage(bundleImageName: "Chat/Input/Accessory Panels/MessageSelectionThrash"), color: theme.chat.inputPanel.panelControlAccentColor), for: [.normal])
            self.deleteButton.setImage(generateTintedImage(image: UIImage(bundleImageName: "Chat/Input/Accessory Panels/MessageSelectionThrash"), color: theme.chat.inputPanel.panelControlDisabledColor), for: [.disabled])
            self.reportButton.setImage(generateTintedImage(image: UIImage(bundleImageName: "Chat/Input/Accessory Panels/MessageSelectionReport"), color: theme.chat.inputPanel.panelControlAccentColor), for: [.normal])
            self.reportButton.setImage(generateTintedImage(image: UIImage(bundleImageName: "Chat/Input/Accessory Panels/MessageSelectionReport"), color: theme.chat.inputPanel.panelControlDisabledColor), for: [.disabled])
            self.forwardButton.setImage(generateTintedImage(image: UIImage(bundleImageName: "Chat/Input/Accessory Panels/MessageSelectionForward"), color: theme.chat.inputPanel.panelControlAccentColor), for: [.normal])
            self.forwardButton.setImage(generateTintedImage(image: UIImage(bundleImageName: "Chat/Input/Accessory Panels/MessageSelectionForward"), color: theme.chat.inputPanel.panelControlDisabledColor), for: [.disabled])
        }
    }
    
    @objc func deleteButtonPressed() {
        self.interfaceInteraction?.deleteSelectedMessages()
    }
    
    @objc func reportButtonPressed() {
        self.interfaceInteraction?.reportSelectedMessages()
    }
    
    @objc func forwardButtonPressed() {
        self.interfaceInteraction?.forwardSelectedMessages()
    }
    
    @objc func shareButtonPressed() {
        self.interfaceInteraction?.shareSelectedMessages()
    }
    
    override func updateLayout(width: CGFloat, leftInset: CGFloat, rightInset: CGFloat, maxHeight: CGFloat, transition: ContainedViewLayoutTransition, interfaceState: ChatPresentationInterfaceState, metrics: LayoutMetrics) -> CGFloat {
        self.validLayout = (width, leftInset, rightInset, maxHeight, metrics)
        
        let panelHeight = defaultHeight(metrics: metrics)
        
        if self.presentationInterfaceState != interfaceState {
            self.presentationInterfaceState = interfaceState
        }
        if let actions = self.actions {
            self.deleteButton.isEnabled = false
            self.reportButton.isEnabled = false
            self.forwardButton.isEnabled = actions.options.contains(.forward)
            self.shareButton.isEnabled = false
            
            self.deleteButton.isEnabled = !actions.options.intersection([.deleteLocally, .deleteGlobally]).isEmpty
            self.shareButton.isEnabled = !actions.options.intersection([.forward]).isEmpty
            self.reportButton.isEnabled = !actions.options.intersection([.report]).isEmpty
            
            self.deleteButton.isHidden = !self.deleteButton.isEnabled
            self.reportButton.isHidden = !self.reportButton.isEnabled
        } else {
            self.deleteButton.isEnabled = false
            self.deleteButton.isHidden = true
            self.reportButton.isEnabled = false
            self.reportButton.isHidden = true
            self.forwardButton.isEnabled = false
            self.shareButton.isEnabled = false
        }
        
        if self.deleteButton.isHidden && self.reportButton.isHidden {
            if let peer = interfaceState.renderedPeer?.peer as? TelegramChannel, case .broadcast = peer.info {
                self.reportButton.isHidden = false
            } else {
                self.deleteButton.isHidden = false
            }
        }
        
        if self.reportButton.isHidden {
            self.deleteButton.frame = CGRect(origin: CGPoint(x: leftInset, y: 0.0), size: CGSize(width: 57.0, height: panelHeight))
            self.forwardButton.frame = CGRect(origin: CGPoint(x: width - rightInset - 57.0, y: 0.0), size: CGSize(width: 57.0, height: panelHeight))
            self.shareButton.frame = CGRect(origin: CGPoint(x: floor((width - rightInset - 57.0) / 2.0), y: 0.0), size: CGSize(width: 57.0, height: panelHeight))
        } else if !self.deleteButton.isHidden {
            let buttons: [HighlightableButtonNode] = [
                self.deleteButton,
                self.reportButton,
                self.shareButton,
                self.forwardButton
            ]
            let buttonSize = CGSize(width: 57.0, height: panelHeight)
            
            let availableWidth = width - leftInset - rightInset
            let spacing: CGFloat = floor((availableWidth - buttonSize.width * CGFloat(buttons.count)) / CGFloat(buttons.count - 1))
            var offset: CGFloat = leftInset
            for i in 0 ..< buttons.count {
                let button = buttons[i]
                if i == buttons.count - 1 {
                    button.frame = CGRect(origin: CGPoint(x: width - rightInset - buttonSize.width, y: 0.0), size: buttonSize)
                } else {
                    button.frame = CGRect(origin: CGPoint(x: offset, y: 0.0), size: buttonSize)
                }
                offset += buttonSize.width + spacing
            }
        } else {
            self.deleteButton.frame = CGRect(origin: CGPoint(x: leftInset, y: 0.0), size: CGSize(width: 53.0, height: panelHeight))
            self.forwardButton.frame = CGRect(origin: CGPoint(x: width - rightInset - 57.0, y: 0.0), size: CGSize(width: 57.0, height: panelHeight))
            self.reportButton.frame = CGRect(origin: CGPoint(x: leftInset, y: 0.0), size: CGSize(width: 53.0, height: 47.0))
            self.shareButton.frame = CGRect(origin: CGPoint(x: floor((width - rightInset - 57.0) / 2.0), y: 0.0), size: CGSize(width: 57.0, height: panelHeight))
        }
        
        return panelHeight
    }
    
    override func minimalHeight(interfaceState: ChatPresentationInterfaceState, metrics: LayoutMetrics) -> CGFloat {
        return defaultHeight(metrics: metrics)
    }
}
