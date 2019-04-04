import Foundation
import UIKit
import Postbox
import TelegramCore

enum ChatNavigationButtonAction {
    case openChatInfo
    case clearHistory
    case cancelMessageSelection
    case search
}

struct ChatNavigationButton: Equatable {
    let action: ChatNavigationButtonAction
    let buttonItem: UIBarButtonItem
    
    static func ==(lhs: ChatNavigationButton, rhs: ChatNavigationButton) -> Bool {
        return lhs.action == rhs.action && lhs.buttonItem === rhs.buttonItem
    }
}

func leftNavigationButtonForChatInterfaceState(_ presentationInterfaceState: ChatPresentationInterfaceState, strings: PresentationStrings, currentButton: ChatNavigationButton?, target: Any?, selector: Selector?) -> ChatNavigationButton? {
    if let _ = presentationInterfaceState.interfaceState.selectionState {
        if let currentButton = currentButton, currentButton.action == .clearHistory {
            return currentButton
        } else if let peer = presentationInterfaceState.renderedPeer?.peer {
            let canClear: Bool
            if peer is TelegramUser || peer is TelegramGroup || peer is TelegramSecretChat {
                canClear = true
            } else if let peer = peer as? TelegramChannel, case .group = peer.info, peer.addressName == nil {
                canClear = true
            } else {
                canClear = false
            }
            if canClear {
                return ChatNavigationButton(action: .clearHistory, buttonItem: UIBarButtonItem(title: strings.Conversation_ClearAll, style: .plain, target: target, action: selector))
            }
        }
    }
    return nil
}

func rightNavigationButtonForChatInterfaceState(_ presentationInterfaceState: ChatPresentationInterfaceState, strings: PresentationStrings, currentButton: ChatNavigationButton?, target: Any?, selector: Selector?, chatInfoNavigationButton: ChatNavigationButton?) -> ChatNavigationButton? {
    if let _ = presentationInterfaceState.interfaceState.selectionState {
        if let currentButton = currentButton, currentButton.action == .cancelMessageSelection {
            return currentButton
        } else {
            return ChatNavigationButton(action: .cancelMessageSelection, buttonItem: UIBarButtonItem(title: strings.Common_Cancel, style: .plain, target: target, action: selector))
        }
    }
    
    if case .standard(true) = presentationInterfaceState.mode {
    } else if let peer = presentationInterfaceState.renderedPeer?.peer {
        if presentationInterfaceState.accountPeerId == peer.id {
            let buttonItem = UIBarButtonItem(image: PresentationResourcesRootController.navigationCompactSearchIcon(presentationInterfaceState.theme), style: .plain, target: target, action: selector)
            buttonItem.accessibilityLabel = "Info"
            return ChatNavigationButton(action: .search, buttonItem: buttonItem)
        }
    }

    return chatInfoNavigationButton
}
