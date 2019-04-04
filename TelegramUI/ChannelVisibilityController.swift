import Foundation
import Display
import SwiftSignalKit
import Postbox
import TelegramCore

private final class ChannelVisibilityControllerArguments {
    let account: Account
    
    let updateCurrentType: (CurrentChannelType) -> Void
    let updatePublicLinkText: (String?, String) -> Void
    let scrollToPublicLinkText: () -> Void
    let displayPrivateLinkMenu: (String) -> Void
    let setPeerIdWithRevealedOptions: (PeerId?, PeerId?) -> Void
    let revokePeerId: (PeerId) -> Void
    let copyPrivateLink: () -> Void
    let revokePrivateLink: () -> Void
    let sharePrivateLink: () -> Void
    
    init(account: Account, updateCurrentType: @escaping (CurrentChannelType) -> Void, updatePublicLinkText: @escaping (String?, String) -> Void, scrollToPublicLinkText: @escaping () -> Void, displayPrivateLinkMenu: @escaping (String) -> Void, setPeerIdWithRevealedOptions: @escaping (PeerId?, PeerId?) -> Void, revokePeerId: @escaping (PeerId) -> Void, copyPrivateLink: @escaping () -> Void, revokePrivateLink: @escaping () -> Void, sharePrivateLink: @escaping () -> Void) {
        self.account = account
        self.updateCurrentType = updateCurrentType
        self.updatePublicLinkText = updatePublicLinkText
        self.scrollToPublicLinkText = scrollToPublicLinkText
        self.displayPrivateLinkMenu = displayPrivateLinkMenu
        self.setPeerIdWithRevealedOptions = setPeerIdWithRevealedOptions
        self.revokePeerId = revokePeerId
        self.copyPrivateLink = copyPrivateLink
        self.revokePrivateLink = revokePrivateLink
        self.sharePrivateLink = sharePrivateLink
    }
}

private enum ChannelVisibilitySection: Int32 {
    case type
    case link
    case linkActions
}

private enum ChannelVisibilityEntryTag: ItemListItemTag {
    case publicLink
    case privateLink
    
    func isEqual(to other: ItemListItemTag) -> Bool {
        if let other = other as? ChannelVisibilityEntryTag, self == other {
            return true
        } else {
            return false
        }
    }
}

private enum ChannelVisibilityEntry: ItemListNodeEntry {
    case typeHeader(PresentationTheme, String)
    case typePublic(PresentationTheme, String, Bool)
    case typePrivate(PresentationTheme, String, Bool)
    case typeInfo(PresentationTheme, String)
    
    case publicLinkAvailability(PresentationTheme, String, Bool)
    case privateLink(PresentationTheme, String, String?)
    case editablePublicLink(PresentationTheme, String)
    case privateLinkInfo(PresentationTheme, String)
    case privateLinkCopy(PresentationTheme, String)
    case privateLinkRevoke(PresentationTheme, String)
    case privateLinkShare(PresentationTheme, String)
    case publicLinkInfo(PresentationTheme, String)
    case publicLinkStatus(PresentationTheme, String, AddressNameValidationStatus)
    
    case existingLinksInfo(PresentationTheme, String)
    case existingLinkPeerItem(Int32, PresentationTheme, PresentationStrings, PresentationDateTimeFormat, PresentationPersonNameOrder, Peer, ItemListPeerItemEditing, Bool)
    
    var section: ItemListSectionId {
        switch self {
            case .typeHeader, .typePublic, .typePrivate, .typeInfo:
                return ChannelVisibilitySection.type.rawValue
            case .publicLinkAvailability, .privateLink, .editablePublicLink, .privateLinkInfo, .publicLinkInfo, .publicLinkStatus:
                return ChannelVisibilitySection.link.rawValue
            case .privateLinkCopy, .privateLinkRevoke, .privateLinkShare:
                return ChannelVisibilitySection.linkActions.rawValue
            case .existingLinksInfo, .existingLinkPeerItem:
                return ChannelVisibilitySection.link.rawValue
        }
    }
    
    var stableId: Int32 {
        switch self {
            case .typeHeader:
                return 0
            case .typePublic:
                return 1
            case .typePrivate:
                return 2
            case .typeInfo:
                return 3
            
            case .publicLinkAvailability:
                return 4
            case .privateLink:
                return 5
            case .editablePublicLink:
                return 6
            case .privateLinkInfo:
                return 7
            case .privateLinkCopy:
                return 8
            case .privateLinkRevoke:
                return 9
            case .privateLinkShare:
                return 10
            case .publicLinkStatus:
                return 11
            case .publicLinkInfo:
                return 12
            case .existingLinksInfo:
                return 13
            case let .existingLinkPeerItem(index, _, _, _, _, _, _, _):
                return 14 + index
        }
    }
    
    static func ==(lhs: ChannelVisibilityEntry, rhs: ChannelVisibilityEntry) -> Bool {
        switch lhs {
            case let .typeHeader(lhsTheme, lhsTitle):
                if case let .typeHeader(rhsTheme, rhsTitle) = rhs, lhsTheme === rhsTheme, lhsTitle == rhsTitle {
                    return true
                } else {
                    return false
                }
            case let .typePublic(lhsTheme, lhsTitle, lhsSelected):
                if case let .typePublic(rhsTheme, rhsTitle, rhsSelected) = rhs, lhsTheme === rhsTheme, lhsTitle == rhsTitle, lhsSelected == rhsSelected {
                    return true
                } else {
                    return false
                }
            case let .typePrivate(lhsTheme, lhsTitle, lhsSelected):
                if case let .typePrivate(rhsTheme, rhsTitle, rhsSelected) = rhs, lhsTheme === rhsTheme, lhsTitle == rhsTitle, lhsSelected == rhsSelected {
                    return true
                } else {
                    return false
                }
            case let .typeInfo(lhsTheme, lhsText):
                if case let .typeInfo(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .publicLinkAvailability(lhsTheme, lhsText, lhsValue):
                if case let .publicLinkAvailability(rhsTheme, rhsText, rhsValue) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                    return true
                } else {
                    return false
                }
            case let .privateLink(lhsTheme, lhsText, lhsLink):
                if case let .privateLink(rhsTheme, rhsText, rhsLink) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsLink == rhsLink {
                    return true
                } else {
                    return false
                }
            case let .editablePublicLink(lhsTheme, lhsCurrentText):
                if case let .editablePublicLink(rhsTheme, rhsCurrentText) = rhs, lhsTheme === rhsTheme, lhsCurrentText == rhsCurrentText {
                    return true
                } else {
                    return false
                }
            case let .privateLinkInfo(lhsTheme, lhsText):
                if case let .privateLinkInfo(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .privateLinkCopy(lhsTheme, lhsText):
                if case let .privateLinkCopy(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .privateLinkRevoke(lhsTheme, lhsText):
                if case let .privateLinkRevoke(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .privateLinkShare(lhsTheme, lhsText):
                if case let .privateLinkShare(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .publicLinkInfo(lhsTheme, lhsText):
                if case let .publicLinkInfo(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .publicLinkStatus(lhsTheme, lhsText, lhsStatus):
                if case let .publicLinkStatus(rhsTheme, rhsText, rhsStatus) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsStatus == rhsStatus {
                    return true
                } else {
                    return false
                }
            case let .existingLinksInfo(lhsTheme, lhsText):
                if case let .existingLinksInfo(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .existingLinkPeerItem(lhsIndex, lhsTheme, lhsStrings, lhsDateTimeFormat, lhsNameOrder, lhsPeer, lhsEditing, lhsEnabled):
                if case let .existingLinkPeerItem(rhsIndex, rhsTheme, rhsStrings, rhsDateTimeFormat, rhsNameOrder, rhsPeer, rhsEditing, rhsEnabled) = rhs {
                    if lhsIndex != rhsIndex {
                        return false
                    }
                    if lhsTheme !== rhsTheme {
                        return false
                    }
                    if lhsStrings !== rhsStrings {
                        return false
                    }
                    if lhsDateTimeFormat != rhsDateTimeFormat {
                        return false
                    }
                    if lhsNameOrder != rhsNameOrder {
                        return false
                    }
                    if !lhsPeer.isEqual(rhsPeer) {
                        return false
                    }
                    if lhsEditing != rhsEditing {
                        return false
                    }
                    if lhsEnabled != rhsEnabled {
                        return false
                    }
                    return true
                } else {
                    return false
                }
        }
    }
    
    static func <(lhs: ChannelVisibilityEntry, rhs: ChannelVisibilityEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }
    
    func item(_ arguments: ChannelVisibilityControllerArguments) -> ListViewItem {
        switch self {
            case let .typeHeader(theme, title):
                return ItemListSectionHeaderItem(theme: theme, text: title, sectionId: self.section)
            case let .typePublic(theme, text, selected):
                return ItemListCheckboxItem(theme: theme, title: text, style: .left, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                    arguments.updateCurrentType(.publicChannel)
                })
            case let .typePrivate(theme, text, selected):
                return ItemListCheckboxItem(theme: theme, title: text, style: .left, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                    arguments.updateCurrentType(.privateChannel)
                })
            case let .typeInfo(theme, text):
                return ItemListTextItem(theme: theme, text: .plain(text), sectionId: self.section)
            case let .publicLinkAvailability(theme, text, value):
                let attr = NSMutableAttributedString(string: text, textColor: value ? theme.list.freeTextColor : theme.list.freeTextErrorColor)
                attr.addAttribute(.font, value: Font.regular(13), range: NSMakeRange(0, attr.length))
                return ItemListActivityTextItem(displayActivity: value, theme: theme, text: attr, sectionId: self.section)
            case let .privateLink(theme, text, value):
                return ItemListActionItem(theme: theme, title: text, kind: value != nil ? .neutral : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                    if let value = value {
                        arguments.displayPrivateLinkMenu(value)
                    }
                }, tag: ChannelVisibilityEntryTag.privateLink)
            case let .editablePublicLink(theme, currentText):
                return ItemListSingleLineInputItem(theme: theme, title: NSAttributedString(string: "t.me/", textColor: theme.list.itemPrimaryTextColor), text: currentText, placeholder: "", tag: ChannelVisibilityEntryTag.publicLink, sectionId: self.section, textUpdated: { updatedText in
                    arguments.updatePublicLinkText(currentText, updatedText)
                }, receivedFocus: {
                    arguments.scrollToPublicLinkText()
                }, action: {
                })
            case let .privateLinkInfo(theme, text):
                return ItemListTextItem(theme: theme, text: .plain(text), sectionId: self.section)
            case let .privateLinkCopy(theme, text):
                return ItemListActionItem(theme: theme, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                    arguments.copyPrivateLink()
                })
            case let .privateLinkRevoke(theme, text):
                return ItemListActionItem(theme: theme, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                    arguments.revokePrivateLink()
                })
            case let .privateLinkShare(theme, text):
                return ItemListActionItem(theme: theme, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                    arguments.sharePrivateLink()
                })
            case let .publicLinkInfo(theme, text):
                return ItemListTextItem(theme: theme, text: .plain(text), sectionId: self.section)
            case let .publicLinkStatus(theme, text, status):
                var displayActivity = false
                let color: UIColor
                switch status {
                    case .invalidFormat:
                        color = theme.list.freeTextErrorColor
                    case let .availability(availability):
                        switch availability {
                            case .available:
                                color = theme.list.freeTextSuccessColor
                            case .invalid:
                                color = theme.list.freeTextErrorColor
                            case .taken:
                                color = theme.list.freeTextErrorColor
                        }
                    case .checking:
                        color = theme.list.freeTextColor
                        displayActivity = true
                }
                return ItemListActivityTextItem(displayActivity: displayActivity, theme: theme, text: NSAttributedString(string: text, textColor: color), sectionId: self.section)
            case let .existingLinksInfo(theme, text):
                return ItemListTextItem(theme: theme, text: .plain(text), sectionId: self.section)
            case let .existingLinkPeerItem(_, theme, strings, dateTimeFormat, nameDisplayOrder, peer, editing, enabled):
                var label = ""
                if let addressName = peer.addressName {
                    label = "t.me/" + addressName
                }
                return ItemListPeerItem(theme: theme, strings: strings, dateTimeFormat: dateTimeFormat, nameDisplayOrder: nameDisplayOrder, account: arguments.account, peer: peer, presence: nil, text: .text(label), label: .none, editing: editing, switchValue: nil, enabled: enabled, sectionId: self.section, action: nil, setPeerIdWithRevealedOptions: { previousId, id in
                    arguments.setPeerIdWithRevealedOptions(previousId, id)
                }, removePeer: { peerId in
                    arguments.revokePeerId(peerId)
                })
        }
    }
}

private enum CurrentChannelType {
    case publicChannel
    case privateChannel
}

private struct ChannelVisibilityControllerState: Equatable {
    let selectedType: CurrentChannelType?
    let editingPublicLinkText: String?
    let addressNameValidationStatus: AddressNameValidationStatus?
    let updatingAddressName: Bool
    let revealedRevokePeerId: PeerId?
    let revokingPeerId: PeerId?
    let revokingPrivateLink: Bool
    
    init() {
        self.selectedType = nil
        self.editingPublicLinkText = nil
        self.addressNameValidationStatus = nil
        self.updatingAddressName = false
        self.revealedRevokePeerId = nil
        self.revokingPeerId = nil
        self.revokingPrivateLink = false
    }
    
    init(selectedType: CurrentChannelType?, editingPublicLinkText: String?, addressNameValidationStatus: AddressNameValidationStatus?, updatingAddressName: Bool, revealedRevokePeerId: PeerId?, revokingPeerId: PeerId?, revokingPrivateLink: Bool) {
        self.selectedType = selectedType
        self.editingPublicLinkText = editingPublicLinkText
        self.addressNameValidationStatus = addressNameValidationStatus
        self.updatingAddressName = updatingAddressName
        self.revealedRevokePeerId = revealedRevokePeerId
        self.revokingPeerId = revokingPeerId
        self.revokingPrivateLink = revokingPrivateLink
    }
    
    static func ==(lhs: ChannelVisibilityControllerState, rhs: ChannelVisibilityControllerState) -> Bool {
        if lhs.selectedType != rhs.selectedType {
            return false
        }
        if lhs.editingPublicLinkText != rhs.editingPublicLinkText {
            return false
        }
        if lhs.addressNameValidationStatus != rhs.addressNameValidationStatus {
            return false
        }
        if lhs.updatingAddressName != rhs.updatingAddressName {
            return false
        }
        if lhs.revealedRevokePeerId != rhs.revealedRevokePeerId {
            return false
        }
        if lhs.revokingPeerId != rhs.revokingPeerId {
            return false
        }
        if lhs.revokingPrivateLink != rhs.revokingPrivateLink {
            return false
        }
        
        return true
    }
    
    func withUpdatedSelectedType(_ selectedType: CurrentChannelType?) -> ChannelVisibilityControllerState {
        return ChannelVisibilityControllerState(selectedType: selectedType, editingPublicLinkText: self.editingPublicLinkText, addressNameValidationStatus: self.addressNameValidationStatus, updatingAddressName: self.updatingAddressName, revealedRevokePeerId: self.revealedRevokePeerId, revokingPeerId: self.revokingPeerId, revokingPrivateLink: self.revokingPrivateLink)
    }
    
    func withUpdatedEditingPublicLinkText(_ editingPublicLinkText: String?) -> ChannelVisibilityControllerState {
        return ChannelVisibilityControllerState(selectedType: self.selectedType, editingPublicLinkText: editingPublicLinkText, addressNameValidationStatus: self.addressNameValidationStatus, updatingAddressName: self.updatingAddressName, revealedRevokePeerId: self.revealedRevokePeerId, revokingPeerId: self.revokingPeerId, revokingPrivateLink: self.revokingPrivateLink)
    }
    
    func withUpdatedAddressNameValidationStatus(_ addressNameValidationStatus: AddressNameValidationStatus?) -> ChannelVisibilityControllerState {
        return ChannelVisibilityControllerState(selectedType: self.selectedType, editingPublicLinkText: self.editingPublicLinkText, addressNameValidationStatus: addressNameValidationStatus, updatingAddressName: self.updatingAddressName, revealedRevokePeerId: self.revealedRevokePeerId, revokingPeerId: self.revokingPeerId, revokingPrivateLink: self.revokingPrivateLink)
    }
    
    func withUpdatedUpdatingAddressName(_ updatingAddressName: Bool) -> ChannelVisibilityControllerState {
        return ChannelVisibilityControllerState(selectedType: self.selectedType, editingPublicLinkText: self.editingPublicLinkText, addressNameValidationStatus: self.addressNameValidationStatus, updatingAddressName: updatingAddressName, revealedRevokePeerId: self.revealedRevokePeerId, revokingPeerId: self.revokingPeerId, revokingPrivateLink: self.revokingPrivateLink)
    }
    
    func withUpdatedRevealedRevokePeerId(_ revealedRevokePeerId: PeerId?) -> ChannelVisibilityControllerState {
        return ChannelVisibilityControllerState(selectedType: self.selectedType, editingPublicLinkText: self.editingPublicLinkText, addressNameValidationStatus: self.addressNameValidationStatus, updatingAddressName: updatingAddressName, revealedRevokePeerId: revealedRevokePeerId, revokingPeerId: self.revokingPeerId, revokingPrivateLink: self.revokingPrivateLink)
    }
    
    func withUpdatedRevokingPeerId(_ revokingPeerId: PeerId?) -> ChannelVisibilityControllerState {
        return ChannelVisibilityControllerState(selectedType: self.selectedType, editingPublicLinkText: self.editingPublicLinkText, addressNameValidationStatus: self.addressNameValidationStatus, updatingAddressName: updatingAddressName, revealedRevokePeerId: self.revealedRevokePeerId, revokingPeerId: revokingPeerId, revokingPrivateLink: self.revokingPrivateLink)
    }
    
    func withUpdatedRevokingPrivateLink(_ revokingPrivateLink: Bool) -> ChannelVisibilityControllerState {
        return ChannelVisibilityControllerState(selectedType: self.selectedType, editingPublicLinkText: self.editingPublicLinkText, addressNameValidationStatus: self.addressNameValidationStatus, updatingAddressName: updatingAddressName, revealedRevokePeerId: self.revealedRevokePeerId, revokingPeerId: self.revokingPeerId, revokingPrivateLink: revokingPrivateLink)
    }
}

private func channelVisibilityControllerEntries(presentationData: PresentationData, mode: ChannelVisibilityControllerMode, view: PeerView, publicChannelsToRevoke: [Peer]?, state: ChannelVisibilityControllerState) -> [ChannelVisibilityEntry] {
    var entries: [ChannelVisibilityEntry] = []
    
    if let peer = view.peers[view.peerId] as? TelegramChannel {
        var isGroup = false
        if case .group = peer.info {
            isGroup = true
        }
        
        let selectedType: CurrentChannelType
        if case .privateLink = mode {
            selectedType = .privateChannel
        } else {
            if let current = state.selectedType {
                selectedType = current
            } else {
                if let addressName = peer.addressName, !addressName.isEmpty {
                    selectedType = .publicChannel
                } else {
                    selectedType = .privateChannel
                }
            }
        }
        
        let currentAddressName: String
        if let current = state.editingPublicLinkText {
            currentAddressName = current
        } else {
            if let addressName = peer.addressName {
                currentAddressName = addressName
            } else {
                currentAddressName = ""
            }
        }
        
        switch mode {
            case .privateLink:
                break
            case .initialSetup, .generic:
                entries.append(.typeHeader(presentationData.theme, isGroup ? presentationData.strings.Group_Setup_TypeHeader : presentationData.strings.Channel_Edit_LinkItem))
                entries.append(.typePublic(presentationData.theme, presentationData.strings.Channel_Setup_TypePublic, selectedType == .publicChannel))
                entries.append(.typePrivate(presentationData.theme, presentationData.strings.Channel_Setup_TypePrivate, selectedType == .privateChannel))
        
                switch selectedType {
                    case .publicChannel:
                        if isGroup {
                            entries.append(.typeInfo(presentationData.theme, presentationData.strings.Group_Setup_TypePublicHelp))
                        } else {
                            entries.append(.typeInfo(presentationData.theme, presentationData.strings.Channel_Setup_TypePublicHelp))
                        }
                    case .privateChannel:
                        if isGroup {
                            entries.append(.typeInfo(presentationData.theme, presentationData.strings.Group_Setup_TypePrivateHelp))
                        } else {
                            entries.append(.typeInfo(presentationData.theme, presentationData.strings.Channel_Setup_TypePrivateHelp))
                        }
                }
        }

        switch selectedType {
            case .publicChannel:
                var displayAvailability = false
                if peer.addressName == nil {
                    displayAvailability = publicChannelsToRevoke == nil || !(publicChannelsToRevoke!.isEmpty)
                }
                
                if displayAvailability {
                    if let publicChannelsToRevoke = publicChannelsToRevoke {
                        entries.append(.publicLinkAvailability(presentationData.theme, presentationData.strings.Group_Username_RemoveExistingUsernamesInfo, false))
                        var index: Int32 = 0
                        for peer in publicChannelsToRevoke.sorted(by: { lhs, rhs in
                            var lhsDate: Int32 = 0
                            var rhsDate: Int32 = 0
                            if let lhs = lhs as? TelegramChannel {
                                lhsDate = lhs.creationDate
                            }
                            if let rhs = rhs as? TelegramChannel {
                                rhsDate = rhs.creationDate
                            }
                            return lhsDate > rhsDate
                        }) {
                            entries.append(.existingLinkPeerItem(index, presentationData.theme, presentationData.strings, presentationData.dateTimeFormat, presentationData.nameDisplayOrder, peer, ItemListPeerItemEditing(editable: true, editing: true, revealed: state.revealedRevokePeerId == peer.id), state.revokingPeerId == nil))
                            index += 1
                        }
                    } else {
                        entries.append(.publicLinkAvailability(presentationData.theme, presentationData.strings.Group_Username_CreatePublicLinkHelp, true))
                    }
                } else {
                    entries.append(.editablePublicLink(presentationData.theme, currentAddressName))
                    if let status = state.addressNameValidationStatus {
                        let text: String
                        switch status {
                            case let .invalidFormat(error):
                                switch error {
                                    case .startsWithDigit:
                                        if isGroup {
                                            text = presentationData.strings.Group_Username_InvalidStartsWithNumber
                                        } else {
                                            text = presentationData.strings.Channel_Username_InvalidStartsWithNumber
                                        }
                                    case .startsWithUnderscore:
                                        text = presentationData.strings.Channel_Username_InvalidCharacters
                                    case .endsWithUnderscore:
                                        text = presentationData.strings.Channel_Username_InvalidCharacters
                                    case .tooShort:
                                        if isGroup {
                                            text = presentationData.strings.Group_Username_InvalidTooShort
                                        } else {
                                            text = presentationData.strings.Channel_Username_InvalidTooShort
                                        }
                                    case .invalidCharacters:
                                        text = presentationData.strings.Channel_Username_InvalidCharacters
                                }
                            case let .availability(availability):
                                switch availability {
                                    case .available:
                                        text = presentationData.strings.Channel_Username_UsernameIsAvailable(currentAddressName).0
                                    case .invalid:
                                        text = presentationData.strings.Channel_Username_InvalidCharacters
                                    case .taken:
                                        text = presentationData.strings.Channel_Username_InvalidTaken
                                }
                            case .checking:
                                text = presentationData.strings.Channel_Username_CheckingUsername
                        }
                        
                        entries.append(.publicLinkStatus(presentationData.theme, text, status))
                    }
                    if isGroup {
                        entries.append(.publicLinkInfo(presentationData.theme, presentationData.strings.Group_Username_CreatePublicLinkHelp))
                    } else {
                        entries.append(.publicLinkInfo(presentationData.theme, presentationData.strings.Channel_Username_CreatePublicLinkHelp))
                    }
                }
            case .privateChannel:
                let link = (view.cachedData as? CachedChannelData)?.exportedInvitation?.link
                let text: String
                if let link = link {
                    text = link
                } else {
                    text = presentationData.strings.Channel_NotificationLoading
                }
                entries.append(.privateLink(presentationData.theme, text, link))
                if isGroup {
                    entries.append(.privateLinkInfo(presentationData.theme, presentationData.strings.Group_Username_CreatePrivateLinkHelp))
                } else {
                    entries.append(.privateLinkInfo(presentationData.theme, presentationData.strings.Channel_Username_CreatePrivateLinkHelp))
                }
                switch mode {
                    case .initialSetup:
                        break
                    case .generic, .privateLink:
                        entries.append(.privateLinkCopy(presentationData.theme, presentationData.strings.GroupInfo_InviteLink_CopyLink))
                        entries.append(.privateLinkRevoke(presentationData.theme, presentationData.strings.GroupInfo_InviteLink_RevokeLink))
                        entries.append(.privateLinkShare(presentationData.theme, presentationData.strings.GroupInfo_InviteLink_ShareLink))
                }
        }
    } else if let _ = view.peers[view.peerId] as? TelegramGroup {
        switch mode {
            case .privateLink:
                let link = (view.cachedData as? CachedGroupData)?.exportedInvitation?.link
                let text: String
                if let link = link {
                    text = link
                } else {
                    text = presentationData.strings.Channel_NotificationLoading
                }
                entries.append(.privateLink(presentationData.theme, text, link))
                entries.append(.privateLinkInfo(presentationData.theme, presentationData.strings.GroupInfo_InviteLink_Help))
                switch mode {
                    case .initialSetup:
                        break
                    case .generic, .privateLink:
                        entries.append(.privateLinkCopy(presentationData.theme, presentationData.strings.GroupInfo_InviteLink_CopyLink))
                        entries.append(.privateLinkRevoke(presentationData.theme, presentationData.strings.GroupInfo_InviteLink_RevokeLink))
                        entries.append(.privateLinkShare(presentationData.theme, presentationData.strings.GroupInfo_InviteLink_ShareLink))
                }
            case .generic, .initialSetup:
                let isGroup = true
                
                let selectedType: CurrentChannelType
                if let current = state.selectedType {
                    selectedType = current
                } else {
                    selectedType = .privateChannel
                }
                
                let currentAddressName: String
                if let current = state.editingPublicLinkText {
                    currentAddressName = current
                } else {
                    currentAddressName = ""
                }
                
                entries.append(.typeHeader(presentationData.theme, presentationData.strings.Group_Setup_TypeHeader))
                entries.append(.typePublic(presentationData.theme, presentationData.strings.Channel_Setup_TypePublic, selectedType == .publicChannel))
                entries.append(.typePrivate(presentationData.theme, presentationData.strings.Channel_Setup_TypePrivate, selectedType == .privateChannel))
                
                entries.append(.typeInfo(presentationData.theme, presentationData.strings.Group_Setup_TypePublicHelp))
                
                switch selectedType {
                    case .publicChannel:
                        let displayAvailability = publicChannelsToRevoke == nil || !(publicChannelsToRevoke!.isEmpty)
                        
                        if displayAvailability {
                            if let publicChannelsToRevoke = publicChannelsToRevoke {
                                entries.append(.publicLinkAvailability(presentationData.theme, presentationData.strings.Group_Username_RemoveExistingUsernamesInfo, false))
                                var index: Int32 = 0
                                for peer in publicChannelsToRevoke.sorted(by: { lhs, rhs in
                                    var lhsDate: Int32 = 0
                                    var rhsDate: Int32 = 0
                                    if let lhs = lhs as? TelegramChannel {
                                        lhsDate = lhs.creationDate
                                    }
                                    if let rhs = rhs as? TelegramChannel {
                                        rhsDate = rhs.creationDate
                                    }
                                    return lhsDate > rhsDate
                                }) {
                                    entries.append(.existingLinkPeerItem(index, presentationData.theme, presentationData.strings, presentationData.dateTimeFormat, presentationData.nameDisplayOrder, peer, ItemListPeerItemEditing(editable: true, editing: true, revealed: state.revealedRevokePeerId == peer.id), state.revokingPeerId == nil))
                                    index += 1
                                }
                            } else {
                                entries.append(.publicLinkAvailability(presentationData.theme, presentationData.strings.Group_Username_CreatePublicLinkHelp, true))
                            }
                        } else {
                            entries.append(.editablePublicLink(presentationData.theme, currentAddressName))
                            if let status = state.addressNameValidationStatus {
                                let text: String
                                switch status {
                                case let .invalidFormat(error):
                                    switch error {
                                        case .startsWithDigit:
                                            text = presentationData.strings.Group_Username_InvalidStartsWithNumber
                                        case .startsWithUnderscore:
                                            text = presentationData.strings.Channel_Username_InvalidCharacters
                                        case .endsWithUnderscore:
                                            text = presentationData.strings.Channel_Username_InvalidCharacters
                                        case .tooShort:
                                            text = presentationData.strings.Group_Username_InvalidTooShort
                                        case .invalidCharacters:
                                            text = presentationData.strings.Channel_Username_InvalidCharacters
                                        }
                                case let .availability(availability):
                                    switch availability {
                                    case .available:
                                        text = presentationData.strings.Channel_Username_UsernameIsAvailable(currentAddressName).0
                                    case .invalid:
                                        text = presentationData.strings.Channel_Username_InvalidCharacters
                                    case .taken:
                                        text = presentationData.strings.Channel_Username_InvalidTaken
                                    }
                                case .checking:
                                    text = presentationData.strings.Channel_Username_CheckingUsername
                                }
                                
                                entries.append(.publicLinkStatus(presentationData.theme, text, status))
                            }
                            entries.append(.publicLinkInfo(presentationData.theme, presentationData.strings.Group_Username_CreatePublicLinkHelp))
                        }
                    case .privateChannel:
                        let link = (view.cachedData as? CachedGroupData)?.exportedInvitation?.link
                        let text: String
                        if let link = link {
                            text = link
                        } else {
                            text = presentationData.strings.Channel_NotificationLoading
                        }
                        entries.append(.privateLink(presentationData.theme, text, link))
                        entries.append(.privateLinkInfo(presentationData.theme, presentationData.strings.Group_Username_CreatePrivateLinkHelp))
                        switch mode {
                            case .initialSetup:
                                break
                            case .generic, .privateLink:
                                entries.append(.privateLinkCopy(presentationData.theme, presentationData.strings.GroupInfo_InviteLink_CopyLink))
                                entries.append(.privateLinkRevoke(presentationData.theme, presentationData.strings.GroupInfo_InviteLink_RevokeLink))
                                entries.append(.privateLinkShare(presentationData.theme, presentationData.strings.GroupInfo_InviteLink_ShareLink))
                        }
            }
        }
    }
    
    return entries
}
private func effectiveChannelType(state: ChannelVisibilityControllerState, peer: TelegramChannel) -> CurrentChannelType {
    let selectedType: CurrentChannelType
    if let current = state.selectedType {
        selectedType = current
    } else {
        if let addressName = peer.addressName, !addressName.isEmpty {
            selectedType = .publicChannel
        } else {
            selectedType = .privateChannel
        }
    }
    return selectedType
}

private func updatedAddressName(state: ChannelVisibilityControllerState, peer: Peer) -> String? {
    if let peer = peer as? TelegramChannel {
        let selectedType = effectiveChannelType(state: state, peer: peer)
        
        let currentAddressName: String
        
        switch selectedType {
            case .privateChannel:
                currentAddressName = ""
            case .publicChannel:
                if let current = state.editingPublicLinkText {
                    currentAddressName = current
                } else {
                    if let addressName = peer.addressName {
                        currentAddressName = addressName
                    } else {
                        currentAddressName = ""
                    }
                }
        }
        
        if !currentAddressName.isEmpty {
            if currentAddressName != peer.addressName {
                return currentAddressName
            } else {
                return nil
            }
        } else if peer.addressName != nil {
            return ""
        } else {
            return nil
        }
    } else if let _ = peer as? TelegramGroup {
        let currentAddressName = state.editingPublicLinkText ?? ""
        if !currentAddressName.isEmpty {
            return currentAddressName
        } else {
            return nil
        }
    } else {
        return nil
    }
}

public enum ChannelVisibilityControllerMode {
    case initialSetup
    case generic
    case privateLink
}

public func channelVisibilityController(context: AccountContext, peerId: PeerId, mode: ChannelVisibilityControllerMode, upgradedToSupergroup: @escaping (PeerId, @escaping () -> Void) -> Void) -> ViewController {
    let statePromise = ValuePromise(ChannelVisibilityControllerState(), ignoreRepeated: true)
    let stateValue = Atomic(value: ChannelVisibilityControllerState())
    let updateState: ((ChannelVisibilityControllerState) -> ChannelVisibilityControllerState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }
    
    let peersDisablingAddressNameAssignment = Promise<[Peer]?>()
    peersDisablingAddressNameAssignment.set(.single(nil) |> then(channelAddressNameAssignmentAvailability(account: context.account, peerId: peerId.namespace == Namespaces.Peer.CloudChannel ? peerId : nil) |> mapToSignal { result -> Signal<[Peer]?, NoError> in
        if case .addressNameLimitReached = result {
            return adminedPublicChannels(account: context.account)
                |> map(Optional.init)
        } else {
            return .single([])
        }
    }))
    
    var dismissImpl: (() -> Void)?
    var nextImpl: (() -> Void)?
    var displayPrivateLinkMenuImpl: ((String) -> Void)?
    var scrollToPublicLinkTextImpl: (() -> Void)?
    var presentControllerImpl: ((ViewController, Any?) -> Void)?
    
    let actionsDisposable = DisposableSet()
    
    let checkAddressNameDisposable = MetaDisposable()
    actionsDisposable.add(checkAddressNameDisposable)
    
    let updateAddressNameDisposable = MetaDisposable()
    actionsDisposable.add(updateAddressNameDisposable)
    
    let revokeAddressNameDisposable = MetaDisposable()
    actionsDisposable.add(revokeAddressNameDisposable)
    
    let revokeLinkDisposable = MetaDisposable()
    actionsDisposable.add(revokeLinkDisposable)
    
    actionsDisposable.add( (context.account.viewTracker.peerView(peerId) |> filter { $0.cachedData != nil } |> take(1) |> mapToSignal { view -> Signal<Void, NoError> in
        return ensuredExistingPeerExportedInvitation(account: context.account, peerId: peerId)
    }).start())
    
    let arguments = ChannelVisibilityControllerArguments(account: context.account, updateCurrentType: { type in
        updateState { state in
            return state.withUpdatedSelectedType(type)
        }
    }, updatePublicLinkText: { currentText, text in
        if text.isEmpty {
            checkAddressNameDisposable.set(nil)
            updateState { state in
                return state.withUpdatedEditingPublicLinkText(text).withUpdatedAddressNameValidationStatus(nil)
            }
        } else if currentText == text {
            checkAddressNameDisposable.set(nil)
            updateState { state in
                return state.withUpdatedEditingPublicLinkText(text).withUpdatedAddressNameValidationStatus(nil).withUpdatedAddressNameValidationStatus(nil)
            }
        } else {
            updateState { state in
                return state.withUpdatedEditingPublicLinkText(text)
            }
            
            checkAddressNameDisposable.set((validateAddressNameInteractive(account: context.account, domain: .peer(peerId), name: text)
                |> deliverOnMainQueue).start(next: { result in
                    updateState { state in
                        return state.withUpdatedAddressNameValidationStatus(result)
                    }
                }))
        }
    }, scrollToPublicLinkText: {
        scrollToPublicLinkTextImpl?()
    }, displayPrivateLinkMenu: { text in
        displayPrivateLinkMenuImpl?(text)
    }, setPeerIdWithRevealedOptions: { peerId, fromPeerId in
        updateState { state in
            if (peerId == nil && fromPeerId == state.revealedRevokePeerId) || (peerId != nil && fromPeerId == nil) {
                return state.withUpdatedRevealedRevokePeerId(peerId)
            } else {
                return state
            }
        }
    }, revokePeerId: { peerId in
        updateState { state in
            return state.withUpdatedRevokingPeerId(peerId)
        }
        
        revokeAddressNameDisposable.set((updateAddressName(account: context.account, domain: .peer(peerId), name: nil) |> deliverOnMainQueue).start(error: { _ in
            updateState { state in
                return state.withUpdatedRevokingPeerId(nil)
            }
        }, completed: {
            peersDisablingAddressNameAssignment.set(.single([]) |> delay(0.2, queue: Queue.mainQueue()) |> afterNext { _ in
                updateState { state in
                    return state.withUpdatedRevokingPeerId(nil)
                }
            })
        }))
    }, copyPrivateLink: {
        let _ = (context.account.postbox.transaction { transaction -> String? in
            if let cachedData = transaction.getPeerCachedData(peerId: peerId) {
                if let cachedData = cachedData as? CachedChannelData {
                    return cachedData.exportedInvitation?.link
                } else if let cachedData = cachedData as? CachedGroupData {
                    return cachedData.exportedInvitation?.link
                }
            }
            return nil
        } |> deliverOnMainQueue).start(next: { link in
            if let link = link {
                UIPasteboard.general.string = link
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                presentControllerImpl?(OverlayStatusController(theme: presentationData.theme, strings: presentationData.strings, type: .genericSuccess(presentationData.strings.Username_LinkCopied)), nil)
            }
        })
    }, revokePrivateLink: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let controller = ActionSheetController(presentationTheme: presentationData.theme)
        let dismissAction: () -> Void = { [weak controller] in
            controller?.dismissAnimated()
        }
        controller.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetTextItem(title: presentationData.strings.GroupInfo_InviteLink_RevokeAlert_Text),
                ActionSheetButtonItem(title: presentationData.strings.GroupInfo_InviteLink_RevokeLink, color: .destructive, action: {
                    dismissAction()
                    
                    var revoke = false
                    updateState { state in
                        if !state.revokingPrivateLink {
                            revoke = true
                            return state.withUpdatedRevokingPrivateLink(true)
                        } else {
                            return state
                        }
                    }
                    if revoke {
                        revokeLinkDisposable.set((ensuredExistingPeerExportedInvitation(account: context.account, peerId: peerId, revokeExisted: true) |> deliverOnMainQueue).start(completed: {
                            updateState {
                                $0.withUpdatedRevokingPrivateLink(false)
                            }
                        }))
                    }
                })
            ]),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: { dismissAction() })])
        ])
        presentControllerImpl?(controller, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
    }, sharePrivateLink: {
        let _ = (context.account.postbox.transaction { transaction -> String? in
            if let cachedData = transaction.getPeerCachedData(peerId: peerId) {
                if let cachedData = cachedData as? CachedChannelData {
                    return cachedData.exportedInvitation?.link
                } else if let cachedData = cachedData as? CachedGroupData {
                    return cachedData.exportedInvitation?.link
                }
            }
            return nil
        } |> deliverOnMainQueue).start(next: { link in
            if let link = link {
                let shareController = ShareController(context: context, subject: .url(link))
                presentControllerImpl?(shareController, nil)
            }
        })
    })
    
    
    let peerView = context.account.viewTracker.peerView(peerId)
    |> deliverOnMainQueue
    
    let previousHadNamesToRevoke = Atomic<Bool?>(value: nil)
    
    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get() |> deliverOnMainQueue, peerView, peersDisablingAddressNameAssignment.get() |> deliverOnMainQueue)
    |> deliverOnMainQueue
    |> map { presentationData, state, view, publicChannelsToRevoke -> (ItemListControllerState, (ItemListNodeState<ChannelVisibilityEntry>, ChannelVisibilityEntry.ItemGenerationArguments)) in
        let peer = peerViewMainPeer(view)
        
        var rightNavigationButton: ItemListNavigationButton?
        if let peer = peer as? TelegramChannel {
            var doneEnabled = true
            if let selectedType = state.selectedType {
                switch selectedType {
                    case .privateChannel:
                        break
                    case .publicChannel:
                        if let addressNameValidationStatus = state.addressNameValidationStatus {
                            switch addressNameValidationStatus {
                                case .availability(.available):
                                    break
                                default:
                                    doneEnabled = false
                            }
                        } else {
                            doneEnabled = !(peer.addressName?.isEmpty ?? true)
                        }
                }
            }
            
            rightNavigationButton = ItemListNavigationButton(content: .text(mode == .initialSetup ? presentationData.strings.Common_Next : presentationData.strings.Common_Done), style: state.updatingAddressName ? .activity : .bold, enabled: doneEnabled, action: {
                var updatedAddressNameValue: String?
                updateState { state in
                    updatedAddressNameValue = updatedAddressName(state: state, peer: peer)
                    return state
                }
                
                if let updatedAddressNameValue = updatedAddressNameValue {
                    let invokeAction: () -> Void = {
                        updateState { state in
                            return state.withUpdatedUpdatingAddressName(true)
                        }
                        _ = ApplicationSpecificNotice.markAsSeenSetPublicChannelLink(accountManager: context.sharedContext.accountManager).start()
                        
                        updateAddressNameDisposable.set((updateAddressName(account: context.account, domain: .peer(peerId), name: updatedAddressNameValue.isEmpty ? nil : updatedAddressNameValue) |> timeout(10, queue: Queue.mainQueue(), alternate: .fail(.generic))
                            |> deliverOnMainQueue).start(error: { _ in
                                updateState { state in
                                    return state.withUpdatedUpdatingAddressName(false)
                                }
                                presentControllerImpl?(textAlertController(context: context, title: nil, text: presentationData.strings.Login_UnknownError, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), nil)
                                
                            }, completed: {
                                updateState { state in
                                    return state.withUpdatedUpdatingAddressName(false)
                                }
                                
                                switch mode {
                                case .initialSetup:
                                    nextImpl?()
                                case .generic, .privateLink:
                                    dismissImpl?()
                                }
                            }))
                        
                    }
                    
                    _ = (ApplicationSpecificNotice.getSetPublicChannelLink(accountManager: context.sharedContext.accountManager) |> deliverOnMainQueue).start(next: { showAlert in
                        if showAlert {
                            presentControllerImpl?(textAlertController(context: context, title: nil, text: presentationData.strings.Channel_Edit_PrivatePublicLinkAlert, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_Cancel, action: {}), TextAlertAction(type: .genericAction, title: presentationData.strings.Common_OK, action: invokeAction)]), nil)
                        } else {
                            invokeAction()
                        }
                    })
                } else {
                    switch mode {
                        case .initialSetup:
                            nextImpl?()
                        case .generic, .privateLink:
                            dismissImpl?()
                    }
                }
            })
        } else if let peer = peer as? TelegramGroup {
            var doneEnabled = true
            if let selectedType = state.selectedType {
                switch selectedType {
                    case .privateChannel:
                        break
                    case .publicChannel:
                        if let addressNameValidationStatus = state.addressNameValidationStatus {
                            switch addressNameValidationStatus {
                                case .availability(.available):
                                    break
                                default:
                                    doneEnabled = false
                            }
                        } else {
                            doneEnabled = !(peer.addressName?.isEmpty ?? true)
                        }
                }
            }
            
            rightNavigationButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Done), style: state.updatingAddressName ? .activity : .bold, enabled: doneEnabled, action: {
                var updatedAddressNameValue: String?
                updateState { state in
                    updatedAddressNameValue = updatedAddressName(state: state, peer: peer)
                    return state
                }
                
                if let updatedAddressNameValue = updatedAddressNameValue {
                    let invokeAction: () -> Void = {
                        updateState { state in
                            return state.withUpdatedUpdatingAddressName(true)
                        }
                        _ = ApplicationSpecificNotice.markAsSeenSetPublicChannelLink(accountManager: context.sharedContext.accountManager).start()
                        
                        let signal = convertGroupToSupergroup(account: context.account, peerId: peerId)
                        |> map(Optional.init)
                        |> `catch` { _ -> Signal<PeerId?, NoError> in
                            return .single(nil)
                        }
                        |> mapToSignal { upgradedPeerId -> Signal<PeerId?, NoError> in
                            guard let upgradedPeerId = upgradedPeerId else {
                                return .single(nil)
                            }
                            return updateAddressName(account: context.account, domain: .peer(upgradedPeerId), name: updatedAddressNameValue.isEmpty ? nil : updatedAddressNameValue)
                            |> `catch` { _ -> Signal<Void, NoError> in
                                return .complete()
                            }
                            |> mapToSignal { _ -> Signal<PeerId?, NoError> in
                                return .complete()
                            }
                            |> then(.single(upgradedPeerId))
                        }
                        |> deliverOnMainQueue
                        
                        updateAddressNameDisposable.set((signal
                        |> deliverOnMainQueue).start(next: { updatedPeerId in
                            if let updatedPeerId = updatedPeerId {
                                upgradedToSupergroup(updatedPeerId, {
                                    dismissImpl?()
                                })
                            } else {
                                dismissImpl?()
                            }
                        }, error: { _ in
                            updateState { state in
                                return state.withUpdatedUpdatingAddressName(false)
                            }
                            presentControllerImpl?(textAlertController(context: context, title: nil, text: presentationData.strings.Login_UnknownError, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), nil)
                            
                        }))
                    }
                    
                    _ = (ApplicationSpecificNotice.getSetPublicChannelLink(accountManager: context.sharedContext.accountManager) |> deliverOnMainQueue).start(next: { showAlert in
                        if showAlert {
                            presentControllerImpl?(textAlertController(context: context, title: nil, text: presentationData.strings.Channel_Edit_PrivatePublicLinkAlert, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_Cancel, action: {}), TextAlertAction(type: .genericAction, title: presentationData.strings.Common_OK, action: invokeAction)]), nil)
                        } else {
                            invokeAction()
                        }
                    })
                } else {
                    switch mode {
                        case .initialSetup:
                            nextImpl?()
                        case .generic, .privateLink:
                            dismissImpl?()
                    }
                }
            })
        }
        
        if state.revokingPeerId != nil {
            rightNavigationButton = ItemListNavigationButton(content: .none, style: .activity, enabled: true, action: {})
        }
        
        var isGroup = false
        if let peer = peer as? TelegramChannel {
            if case .group = peer.info {
                isGroup = true
            }
        } else if let _ = peer as? TelegramGroup {
            isGroup = true
        }
        
        let leftNavigationButton: ItemListNavigationButton?
        switch mode {
            case .initialSetup:
                leftNavigationButton = nil
            case .generic, .privateLink:
                leftNavigationButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Cancel), style: .regular, enabled: true, action: {
                    dismissImpl?()
                })
        }
        
        var crossfade: Bool = false
        let hasNamesToRevoke = publicChannelsToRevoke != nil && !publicChannelsToRevoke!.isEmpty
        let hadNamesToRevoke = previousHadNamesToRevoke.swap(hasNamesToRevoke)
        if let peer = view.peers[view.peerId] as? TelegramChannel {
            let selectedType: CurrentChannelType
            if case .privateLink = mode {
                selectedType = .privateChannel
            } else {
                if let current = state.selectedType {
                    selectedType = current
                } else {
                    if let addressName = peer.addressName, !addressName.isEmpty {
                        selectedType = .publicChannel
                    } else {
                        selectedType = .privateChannel
                    }
                }
            }
            
            if selectedType == .publicChannel, let hadNamesToRevoke = hadNamesToRevoke {
                crossfade = hadNamesToRevoke != hasNamesToRevoke
            }
        }
        
        let title: String
        if case .privateLink = mode {
            title = presentationData.strings.GroupInfo_InviteLink_Title
        } else {
            title = isGroup ? presentationData.strings.GroupInfo_GroupType : presentationData.strings.Channel_TypeSetup_Title
        }
        let controllerState = ItemListControllerState(theme: presentationData.theme, title: .text(title), leftNavigationButton: leftNavigationButton, rightNavigationButton: rightNavigationButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(entries: channelVisibilityControllerEntries(presentationData: presentationData, mode: mode, view: view, publicChannelsToRevoke: publicChannelsToRevoke, state: state), style: .blocks, crossfadeState: crossfade, animateChanges: false)
        
        return (controllerState, (listState, arguments))
    } |> afterDisposed {
        actionsDisposable.dispose()
    }
    
    let controller = ItemListController(context: context, state: signal)
    dismissImpl = { [weak controller] in
        controller?.view.endEditing(true)
        controller?.dismiss()
    }
    nextImpl = { [weak controller] in
        if let controller = controller {
            if case .initialSetup = mode {
                let selectionController = ContactMultiselectionController(context: context, mode: .channelCreation, options: [])
                (controller.navigationController as? NavigationController)?.replaceAllButRootController(selectionController, animated: true)
                let _ = (selectionController.result
                    |> deliverOnMainQueue).start(next: { [weak selectionController] peerIds in
                        guard let selectionController = selectionController, let navigationController = selectionController.navigationController as? NavigationController else {
                            return
                        }
                        let filteredPeerIds = peerIds.compactMap({ peerId -> PeerId? in
                            if case let .peer(id) = peerId {
                                return id
                            } else {
                                return nil
                            }
                        })
                        if filteredPeerIds.isEmpty {
                            navigateToChatController(navigationController: navigationController, chatController: nil, context: context, chatLocation: .peer(peerId), keepStack: .never, animated: true)
                        } else {
                            selectionController.displayProgress = true
                            let _ = (addChannelMembers(account: context.account, peerId: peerId, memberIds: filteredPeerIds)
                            |> deliverOnMainQueue).start(completed: { [weak selectionController] in
                                guard let selectionController = selectionController, let navigationController = selectionController.navigationController as? NavigationController else {
                                    return
                                }
                                
                                navigateToChatController(navigationController: navigationController, chatController: nil, context: context, chatLocation: .peer(peerId), keepStack: .never, animated: true)
                            })
                        }
                    })
            } else {
                (controller.navigationController as? NavigationController)?.replaceAllButRootController(ChatController(context: context, chatLocation: .peer(peerId)), animated: true)
            }
        }
    }
    displayPrivateLinkMenuImpl = { [weak controller] text in
        if let strongController = controller {
            var resultItemNode: ListViewItemNode?
            let _ = strongController.frameForItemNode({ itemNode in
                if let itemNode = itemNode as? ItemListActionItemNode {
                    if let tag = itemNode.tag as? ChannelVisibilityEntryTag {
                        if tag == .privateLink {
                            resultItemNode = itemNode
                            return true
                        }
                    }
                }
                return false
            })
            if let resultItemNode = resultItemNode {
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let contextMenuController = ContextMenuController(actions: [ContextMenuAction(content: .text(title: presentationData.strings.Conversation_ContextMenuCopyLink, accessibilityLabel: presentationData.strings.Conversation_ContextMenuCopyLink), action: {
                    UIPasteboard.general.string = text
                })])
                strongController.present(contextMenuController, in: .window(.root), with: ContextMenuControllerPresentationArguments(sourceNodeAndRect: { [weak resultItemNode] in
                    if let strongController = controller, let resultItemNode = resultItemNode {
                        return (resultItemNode, resultItemNode.contentBounds.insetBy(dx: 0.0, dy: -2.0), strongController.displayNode, strongController.view.bounds)
                    } else {
                        return nil
                    }
                }))
            }
        }
    }
    scrollToPublicLinkTextImpl = { [weak controller] in
        DispatchQueue.main.async {
            if let strongController = controller {
                var resultItemNode: ListViewItemNode?
                let _ = strongController.frameForItemNode({ itemNode in
                    if let itemNode = itemNode as? ItemListSingleLineInputItemNode {
                        if let tag = itemNode.tag as? ChannelVisibilityEntryTag {
                            if tag == .publicLink {
                                resultItemNode = itemNode
                                return true
                            }
                        }
                    }
                    return false
                })
                if let resultItemNode = resultItemNode {
                    strongController.ensureItemNodeVisible(resultItemNode)
                }
            }
        }
    }
    presentControllerImpl = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }
    return controller
}
