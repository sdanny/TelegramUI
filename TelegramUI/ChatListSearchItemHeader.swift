import Foundation
import Display

enum ChatListSearchItemHeaderType: Int32 {
    case localPeers
    case members
    case contacts
    case globalPeers
    case deviceContacts
    case recentPeers
    case messages
    case phoneNumber
    case exceptions
}

final class ChatListSearchItemHeader: ListViewItemHeader {
    let id: Int64
    let type: ChatListSearchItemHeaderType
    let stickDirection: ListViewItemHeaderStickDirection = .top
    let theme: PresentationTheme
    let strings: PresentationStrings
    let actionTitle: String?
    let action: (() -> Void)?
    
    let height: CGFloat = 28.0
    
    init(type: ChatListSearchItemHeaderType, theme: PresentationTheme, strings: PresentationStrings, actionTitle: String?, action: (() -> Void)?) {
        self.type = type
        self.id = Int64(self.type.rawValue)
        self.theme = theme
        self.strings = strings
        self.actionTitle = actionTitle
        self.action = action
    }
    
    func node() -> ListViewItemHeaderNode {
        return ChatListSearchItemHeaderNode(type: self.type, theme: self.theme, strings: self.strings, actionTitle: self.actionTitle, action: self.action)
    }
}

final class ChatListSearchItemHeaderNode: ListViewItemHeaderNode {
    private let type: ChatListSearchItemHeaderType
    private var theme: PresentationTheme
    private var strings: PresentationStrings
    private let actionTitle: String?
    private let action: (() -> Void)?
    
    private let sectionHeaderNode: ListSectionHeaderNode
    
    init(type: ChatListSearchItemHeaderType, theme: PresentationTheme, strings: PresentationStrings, actionTitle: String?, action: (() -> Void)?) {
        self.type = type
        self.theme = theme
        self.strings = strings
        self.actionTitle = actionTitle
        self.action = action
        
        self.sectionHeaderNode = ListSectionHeaderNode(theme: theme)
        
        super.init()
        
        switch type {
            case .localPeers:
                self.sectionHeaderNode.title = strings.DialogList_SearchSectionDialogs.uppercased()
            case .members:
                self.sectionHeaderNode.title = strings.Compose_NewChannel_Members.uppercased()
            case .contacts:
                self.sectionHeaderNode.title = strings.Contacts_TopSection.uppercased()
            case .globalPeers:
                self.sectionHeaderNode.title = strings.DialogList_SearchSectionGlobal.uppercased()
            case .deviceContacts:
                self.sectionHeaderNode.title = strings.Contacts_NotRegisteredSection.uppercased()
            case .messages:
                self.sectionHeaderNode.title = strings.DialogList_SearchSectionMessages.uppercased()
            case .recentPeers:
                self.sectionHeaderNode.title = strings.DialogList_SearchSectionRecent.uppercased()
            case .phoneNumber:
                self.sectionHeaderNode.title = strings.Contacts_PhoneNumber.uppercased()
            case .exceptions:
                self.sectionHeaderNode.title = strings.GroupInfo_Permissions_Exceptions.uppercased()
        }
        
        self.sectionHeaderNode.action = actionTitle
        self.sectionHeaderNode.activateAction = action
        
        self.addSubnode(self.sectionHeaderNode)
    }
    
    func updateTheme(theme: PresentationTheme) {
        self.theme = theme
        self.sectionHeaderNode.updateTheme(theme: theme)
    }
    
    override func updateLayout(size: CGSize, leftInset: CGFloat, rightInset: CGFloat) {
        self.sectionHeaderNode.frame = CGRect(origin: CGPoint(), size: size)
        self.sectionHeaderNode.updateLayout(size: size, leftInset: leftInset, rightInset: rightInset)
    }
    
    override func animateRemoved(duration: Double) {
        self.alpha = 0.0
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: duration, removeOnCompletion: false)
    }
}
