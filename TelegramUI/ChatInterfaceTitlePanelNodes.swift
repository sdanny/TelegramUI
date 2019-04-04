import Foundation
import TelegramCore

func titlePanelForChatPresentationInterfaceState(_ chatPresentationInterfaceState: ChatPresentationInterfaceState, context: AccountContext, currentPanel: ChatTitleAccessoryPanelNode?, interfaceInteraction: ChatPanelInterfaceInteraction?) -> ChatTitleAccessoryPanelNode? {
    if case .overlay = chatPresentationInterfaceState.mode {
        return nil
    }
    if chatPresentationInterfaceState.renderedPeer?.peer?.restrictionText != nil {
        return nil
    }
    if chatPresentationInterfaceState.search != nil {
        return nil
    }
    var selectedContext: ChatTitlePanelContext?
    if !chatPresentationInterfaceState.titlePanelContexts.isEmpty {
        loop: for context in chatPresentationInterfaceState.titlePanelContexts.reversed() {
            switch context {
                case .pinnedMessage:
                    if let pinnedMessage = chatPresentationInterfaceState.pinnedMessage, pinnedMessage.id != chatPresentationInterfaceState.interfaceState.messageActionsState.closedPinnedMessageId {
                        selectedContext = context
                        break loop
                    }
                case .chatInfo, .requestInProgress, .toastAlert:
                    selectedContext = context
                    break loop
            }
        }
    }
    
    if chatPresentationInterfaceState.canReportPeer && (selectedContext == nil || selectedContext! <= .pinnedMessage) {
        if let currentPanel = currentPanel as? ChatReportPeerTitlePanelNode {
            return currentPanel
        } else {
            let panel = ChatReportPeerTitlePanelNode()
            panel.interfaceInteraction = interfaceInteraction
            return panel
        }
    }
    
    if let selectedContext = selectedContext {
        switch selectedContext {
            case .pinnedMessage:
                if let currentPanel = currentPanel as? ChatPinnedMessageTitlePanelNode {
                    return currentPanel
                } else {
                    let panel = ChatPinnedMessageTitlePanelNode(context: context)
                    panel.interfaceInteraction = interfaceInteraction
                    return panel
                }
            case .chatInfo:
                if let currentPanel = currentPanel as? ChatInfoTitlePanelNode {
                    return currentPanel
                } else {
                    let panel = ChatInfoTitlePanelNode()
                    panel.interfaceInteraction = interfaceInteraction
                    return panel
                }
            case .requestInProgress:
                if let currentPanel = currentPanel as? ChatRequestInProgressTitlePanelNode {
                    return currentPanel
                } else {
                    let panel = ChatRequestInProgressTitlePanelNode()
                    panel.interfaceInteraction = interfaceInteraction
                    return panel
                }
            case let .toastAlert(text):
                if let currentPanel = currentPanel as? ChatToastAlertPanelNode {
                    currentPanel.text = text
                    return currentPanel
                } else {
                    let panel = ChatToastAlertPanelNode()
                    panel.text = text
                    panel.interfaceInteraction = interfaceInteraction
                    return panel
                }
        }
    }
    
    return nil
}
