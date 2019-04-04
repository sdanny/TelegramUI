import Foundation
import Display
import AsyncDisplayKit
import SwiftSignalKit
import Postbox
import TelegramCore

private let dropDownIcon = { () -> UIImage in
    UIGraphicsBeginImageContextWithOptions(CGSize(width: 12.0, height: 12.0), false, 0.0)
    let context = UIGraphicsGetCurrentContext()!
    context.setBlendMode(.copy)
    context.setFillColor(UIColor.black.cgColor)
    context.move(to: CGPoint(x: 0.0, y: 3.0))
    context.addLine(to: CGPoint(x: 12.0, y: 3.0))
    context.addLine(to: CGPoint(x: 6.0, y: 9.0))
    context.fillPath()
    let image = UIGraphicsGetImageFromCurrentImageContext()!
    UIGraphicsEndImageContext()
    return image
}()

private enum ContactListNodeEntryId: Hashable {
    case search
    case sort
    case permission(action: Bool)
    case option(index: Int)
    case peerId(Int64)
    case deviceContact(DeviceContactStableId)
    
    var hashValue: Int {
        switch self {
            case .search:
                return 0
            case .sort:
                return 1
            case let .permission(action):
                return (action ? 3 : 2).hashValue
            case let .option(index):
                return (index + 4).hashValue
            case let .peerId(peerId):
                return peerId.hashValue
            case let .deviceContact(id):
                return id.hashValue
        }
    }
    
    static func <(lhs: ContactListNodeEntryId, rhs: ContactListNodeEntryId) -> Bool {
        return lhs.hashValue < rhs.hashValue
    }

    static func ==(lhs: ContactListNodeEntryId, rhs: ContactListNodeEntryId) -> Bool {
        switch lhs {
            case .search:
                switch rhs {
                    case .search:
                        return true
                    default:
                        return false
                }
            case .sort:
                switch rhs {
                    case .sort:
                        return true
                    default:
                        return false
                }
            case let .permission(action):
                if case .permission(action) = rhs {
                    return true
                } else {
                    return false
                }
            case let .option(index):
                if case .option(index) = rhs {
                    return true
                } else {
                    return false
                }
            case let .peerId(lhsId):
                switch rhs {
                    case let .peerId(rhsId):
                        return lhsId == rhsId
                    default:
                        return false
                }
            case let .deviceContact(id):
                if case .deviceContact(id) = rhs {
                    return true
                } else {
                    return false
                }
        }
    }
}

private final class ContactListNodeInteraction {
    let activateSearch: () -> Void
    let openSortMenu: () -> Void
    let authorize: () -> Void
    let suppressWarning: () -> Void
    let openPeer: (ContactListPeer) -> Void
    
    init(activateSearch: @escaping () -> Void, openSortMenu: @escaping () -> Void, authorize: @escaping () -> Void, suppressWarning: @escaping () -> Void, openPeer: @escaping (ContactListPeer) -> Void) {
        self.activateSearch = activateSearch
        self.openSortMenu = openSortMenu
        self.authorize = authorize
        self.suppressWarning = suppressWarning
        self.openPeer = openPeer
    }
}

enum ContactListAnimation {
    case none
    case `default`
    case insertion
}

enum ContactListPeerId: Hashable {
    case peer(PeerId)
    case deviceContact(DeviceContactStableId)
}

enum ContactListPeer: Equatable {
    case peer(peer: Peer, isGlobal: Bool)
    case deviceContact(DeviceContactStableId, DeviceContactBasicData)
    
    var id: ContactListPeerId {
        switch self {
            case let .peer(peer, _):
                return .peer(peer.id)
            case let .deviceContact(id, _):
                return .deviceContact(id)
        }
    }
    
    var indexName: PeerIndexNameRepresentation {
        switch self {
            case let .peer(peer, _):
                return peer.indexName
            case let .deviceContact(_, contact):
                return .personName(first: contact.firstName, last: contact.lastName, addressName: "", phoneNumber: "")
        }
    }
    
    static func ==(lhs: ContactListPeer, rhs: ContactListPeer) -> Bool {
        switch lhs {
            case let .peer(lhsPeer, lhsIsGlobal):
                if case let .peer(rhsPeer, rhsIsGlobal) = rhs, lhsPeer.isEqual(rhsPeer), lhsIsGlobal == rhsIsGlobal {
                    return true
                } else {
                    return false
                }
            case let .deviceContact(id, contact):
                if case .deviceContact(id, contact) = rhs {
                    return true
                } else {
                    return false
                }
        }
    }
}

private enum ContactListNodeEntry: Comparable, Identifiable {
    case search(PresentationTheme, PresentationStrings)
    case sort(PresentationTheme, PresentationStrings, ContactsSortOrder)
    case permissionInfo(PresentationTheme, PresentationStrings, Bool)
    case permissionEnable(PresentationTheme, String)
    case option(Int, ContactListAdditionalOption, ListViewItemHeader?, PresentationTheme, PresentationStrings)
    case peer(Int, ContactListPeer, PeerPresence?, ListViewItemHeader?, ContactsPeerItemSelection, PresentationTheme, PresentationStrings, PresentationDateTimeFormat, PresentationPersonNameOrder, PresentationPersonNameOrder, Bool)
    
    var stableId: ContactListNodeEntryId {
        switch self {
            case .search:
                return .search
            case .sort:
                return .sort
            case .permissionInfo:
                return .permission(action: false)
            case .permissionEnable:
                return .permission(action: true)
            case let .option(index, _, _, _, _):
                return .option(index: index)
            case let .peer(_, peer, _, _, _, _, _, _, _, _, _):
                switch peer {
                    case let .peer(peer, _):
                        return .peerId(peer.id.toInt64())
                    case let .deviceContact(id, _):
                        return .deviceContact(id)
                }
        }
    }
    
    func item(account: Account, interaction: ContactListNodeInteraction) -> ListViewItem {
        switch self {
            case let .search(theme, strings):
                return ChatListSearchItem(theme: theme, placeholder: strings.Contacts_SearchLabel, activate: {
                    interaction.activateSearch()
                })
            case let .sort(theme, strings, sortOrder):
                var text = strings.Contacts_SortedByName
                if case .presence = sortOrder {
                    text = strings.Contacts_SortedByPresence
                }
                return ContactListActionItem(theme: theme, title: text, icon: .inline(dropDownIcon, .right), highlight: .alpha, header: nil, action: {
                    interaction.openSortMenu()
            })
            case let .permissionInfo(theme, strings, suppressed):
                return PermissionInfoItem(theme: theme, strings: strings, subject: .contacts, type: .denied, style: .plain, suppressed: suppressed, close: {
                    interaction.suppressWarning()
                })
            case let .permissionEnable(theme, text):
                return ContactListActionItem(theme: theme, title: text, icon: .none, header: nil, action: {
                    interaction.authorize()
                })
            case let .option(_, option, header, theme, _):
                return ContactListActionItem(theme: theme, title: option.title, icon: option.icon, header: header, action: option.action)
            case let .peer(_, peer, presence, header, selection, theme, strings, dateTimeFormat, nameSortOrder, nameDisplayOrder, enabled):
                let status: ContactsPeerItemStatus
                let itemPeer: ContactsPeerItemPeer
                switch peer {
                    case let .peer(peer, isGlobal):
                        if isGlobal, let _ = peer.addressName {
                            status = .addressName("")
                        } else {
                            let presence = presence ?? TelegramUserPresence(status: .none, lastActivity: 0)
                            status = .presence(presence, dateTimeFormat)
                        }
                        itemPeer = .peer(peer: peer, chatPeer: peer)
                    case let .deviceContact(id, contact):
                        status = .none
                        itemPeer = .deviceContact(stableId: id, contact: contact)
                }
                return ContactsPeerItem(theme: theme, strings: strings, sortOrder: nameSortOrder, displayOrder: nameDisplayOrder, account: account, peerMode: .peer, peer: itemPeer, status: status, enabled: enabled, selection: selection, editing: ContactsPeerItemEditing(editable: false, editing: false, revealed: false), index: nil, header: header, action: { _ in
                    interaction.openPeer(peer)
                })
        }
    }

    static func ==(lhs: ContactListNodeEntry, rhs: ContactListNodeEntry) -> Bool {
        switch lhs {
            case let .search(lhsTheme, lhsStrings):
                if case let .search(rhsTheme, rhsStrings) = rhs, lhsTheme === rhsTheme, lhsStrings === rhsStrings {
                    return true
                } else {
                    return false
                }
            case let .sort(lhsTheme, lhsStrings, lhsSortOrder):
                if case let .sort(rhsTheme, rhsStrings, rhsSortOrder) = rhs, lhsTheme === rhsTheme, lhsStrings === rhsStrings, lhsSortOrder == rhsSortOrder {
                    return true
                } else {
                    return false
                }
            case let .permissionInfo(lhsTheme, lhsStrings, lhsSuppressed):
                if case let .permissionInfo(rhsTheme, rhsStrings, rhsSuppressed) = rhs, lhsTheme === rhsTheme, lhsStrings === rhsStrings, lhsSuppressed == rhsSuppressed {
                    return true
                } else {
                    return false
                }
            case let .permissionEnable(lhsTheme, lhsText):
                if case let .permissionEnable(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .option(lhsIndex, lhsOption, lhsHeader, lhsTheme, lhsStrings):
                if case let .option(rhsIndex, rhsOption, rhsHeader, rhsTheme, rhsStrings) = rhs, lhsIndex == rhsIndex, lhsOption == rhsOption, lhsHeader?.id == rhsHeader?.id, lhsTheme === rhsTheme, lhsStrings === rhsStrings {
                    return true
                } else {
                    return false
                }
            case let .peer(lhsIndex, lhsPeer, lhsPresence, lhsHeader, lhsSelection, lhsTheme, lhsStrings, lhsTimeFormat, lhsSortOrder, lhsDisplayOrder, lhsEnabled):
                switch rhs {
                    case let .peer(rhsIndex, rhsPeer, rhsPresence, rhsHeader, rhsSelection, rhsTheme, rhsStrings, rhsTimeFormat, rhsSortOrder, rhsDisplayOrder, rhsEnabled):
                        if lhsIndex != rhsIndex {
                            return false
                        }
                        if lhsPeer != rhsPeer {
                            return false
                        }
                        if let lhsPresence = lhsPresence, let rhsPresence = rhsPresence {
                            if !lhsPresence.isEqual(to: rhsPresence) {
                                return false
                            }
                        } else if (lhsPresence != nil) != (rhsPresence != nil) {
                            return false
                        }
                        if lhsHeader?.id != rhsHeader?.id {
                            return false
                        }
                        if lhsSelection != rhsSelection {
                            return false
                        }
                        if lhsTheme !== rhsTheme {
                            return false
                        }
                        if lhsStrings !== rhsStrings {
                            return false
                        }
                        if lhsTimeFormat != rhsTimeFormat {
                            return false
                        }
                        if lhsSortOrder != rhsSortOrder {
                            return false
                        }
                        if lhsDisplayOrder != rhsDisplayOrder {
                            return false
                        }
                        if lhsEnabled != rhsEnabled {
                            return false
                        }
                        return true
                    default:
                        return false
                }
        }
    }

    static func <(lhs: ContactListNodeEntry, rhs: ContactListNodeEntry) -> Bool {
        switch lhs {
            case .search:
                return true
            case .sort:
                switch rhs {
                    case .search:
                        return false
                    default:
                        return true
                }
            case .permissionInfo:
                switch rhs {
                    case .search, .sort:
                        return false
                    default:
                        return true
                }
            case .permissionEnable:
                switch rhs {
                    case .search, .sort, .permissionInfo:
                        return false
                    default:
                        return true
                }
            case let .option(lhsIndex, _, _, _, _):
                switch rhs {
                    case .search, .sort, .permissionInfo, .permissionEnable:
                            return false
                        case let .option(rhsIndex, _, _, _, _):
                            return lhsIndex < rhsIndex
                        case .peer:
                            return true
                }
            case let .peer(lhsIndex, _, _, _, _, _, _, _, _, _, _):
                switch rhs {
                    case .search, .sort, .permissionInfo, .permissionEnable, .option:
                        return false
                    case let .peer(rhsIndex, _, _, _, _, _, _, _, _, _, _):
                        return lhsIndex < rhsIndex
                }
        }
    }
}

private extension PeerIndexNameRepresentation {
    func isLessThan(other: PeerIndexNameRepresentation, ordering: PresentationPersonNameOrder) -> ComparisonResult {
        switch self {
            case let .title(lhsTitle, _):
                let rhsString: String
                switch other {
                    case let .title(title, _):
                        rhsString = title
                    case let .personName(first, last, _, _):
                        switch ordering {
                            case .firstLast:
                                if first.isEmpty {
                                    rhsString = last
                                } else {
                                    rhsString = first + last
                                }
                            case .lastFirst:
                                if last.isEmpty {
                                    rhsString = first
                                } else {
                                    rhsString = last + first
                                }
                        }
                }
                return lhsTitle.caseInsensitiveCompare(rhsString)
            case let .personName(lhsFirst, lhsLast, _, _):
                let lhsString: String
                switch ordering {
                    case .firstLast:
                        if lhsFirst.isEmpty {
                            lhsString = lhsLast
                        } else {
                            lhsString = lhsFirst + lhsLast
                        }
                    case .lastFirst:
                        if lhsLast.isEmpty {
                            lhsString = lhsFirst
                        } else {
                            lhsString = lhsLast + lhsFirst
                        }
                }
                let rhsString: String
                switch other {
                    case let .title(title, _):
                        rhsString = title
                    case let .personName(first, last, _, _):
                        switch ordering {
                            case .firstLast:
                                if first.isEmpty {
                                    rhsString = last
                                } else {
                                    rhsString = first + last
                                }
                            case .lastFirst:
                                if last.isEmpty {
                                    rhsString = first
                                } else {
                                    rhsString = last + first
                                }
                        }
                }
                return lhsString.caseInsensitiveCompare(rhsString)
        }
    }
}

private func contactListNodeEntries(accountPeer: Peer?, peers: [ContactListPeer], presences: [PeerId: PeerPresence], presentation: ContactListPresentation, selectionState: ContactListNodeGroupSelectionState?, theme: PresentationTheme, strings: PresentationStrings, dateTimeFormat: PresentationDateTimeFormat, sortOrder: PresentationPersonNameOrder, displayOrder: PresentationPersonNameOrder, disabledPeerIds:Set<PeerId>, authorizationStatus: AccessType, warningSuppressed: (Bool, Bool), displaySortOptions: Bool) -> [ContactListNodeEntry] {
    var entries: [ContactListNodeEntry] = []
    
    var commonHeader: ListViewItemHeader?
    var orderedPeers: [ContactListPeer]
    var headers: [ContactListPeerId: ContactListNameIndexHeader] = [:]
    
    if displaySortOptions, let sortOrder = presentation.sortOrder {
        entries.append(.sort(theme, strings, sortOrder))
    }
    
    var addHeader = false
    if #available(iOSApplicationExtension 10.0, *) {
        let (suppressed, syncDisabled) = warningSuppressed
        if !peers.isEmpty && !syncDisabled {
            switch authorizationStatus {
            case .denied:
                entries.append(.permissionInfo(theme, strings, suppressed))
                entries.append(.permissionEnable(theme, strings.Permissions_ContactsAllowInSettings_v0))
                addHeader = true
            case .notDetermined:
                entries.append(.permissionInfo(theme, strings, false))
                entries.append(.permissionEnable(theme, strings.Permissions_ContactsAllow_v0))
                addHeader = true
            default:
                break
            }
        }
    }
    
    if addHeader {
        commonHeader = ChatListSearchItemHeader(type: .contacts, theme: theme, strings: strings, actionTitle: nil, action: nil)
    }
    
    switch presentation {
        case let .orderedByPresence(options):
            orderedPeers = peers.sorted(by: { lhs, rhs in
                if case let .peer(lhsPeer, _) = lhs, case let .peer(rhsPeer, _) = rhs {
                    let lhsPresence = presences[lhsPeer.id]
                    let rhsPresence = presences[rhsPeer.id]
                    if let lhsPresence = lhsPresence as? TelegramUserPresence, let rhsPresence = rhsPresence as? TelegramUserPresence {
                        if lhsPresence.status < rhsPresence.status {
                            return false
                        } else if lhsPresence.status > rhsPresence.status {
                            return true
                        }
                    } else if let _ = lhsPresence {
                        return true
                    } else if let _ = rhsPresence {
                        return false
                    }
                    return lhsPeer.id < rhsPeer.id
                } else if case .peer = lhs {
                    return true
                } else {
                    return false
                }
            })
            for i in 0 ..< options.count {
                entries.append(.option(i, options[i], commonHeader, theme, strings))
            }
        case let .natural(options):
            let sortedPeers = peers.sorted(by: { lhs, rhs in
                let result = lhs.indexName.isLessThan(other: rhs.indexName, ordering: sortOrder)
                if result == .orderedSame {
                    if case let .peer(lhsPeer, _) = lhs, case let .peer(rhsPeer, _) = rhs {
                        return lhsPeer.id < rhsPeer.id
                    } else if case let .deviceContact(lhsId, _) = lhs, case let .deviceContact(rhsId, _) = rhs {
                        return lhsId < rhsId
                    } else if case .peer = lhs {
                        return true
                    } else {
                        return false
                    }
                } else {
                    return result == .orderedAscending
                }
            })
            var headerCache: [unichar: ContactListNameIndexHeader] = [:]
            var startsWithLetter: [ContactListPeer] = []
            var startsWithOther: [ContactListPeer] = []
            let hashHeader = "#".utf16.first!
            
            for peer in sortedPeers {
                var indexHeader: unichar = 35
                switch peer.indexName {
                    case let .title(title, _):
                        if let c = title.folding(options: .diacriticInsensitive, locale: .current).uppercased().utf16.first {
                            indexHeader = c
                        }
                    case let .personName(first, last, _, _):
                        switch sortOrder {
                            case .firstLast:
                                if let c = first.folding(options: .diacriticInsensitive, locale: .current).uppercased().utf16.first {
                                    indexHeader = c
                                } else if let c = last.folding(options: .diacriticInsensitive, locale: .current).uppercased().utf16.first {
                                    indexHeader = c
                                }
                            case .lastFirst:
                                if let c = last.folding(options: .diacriticInsensitive, locale: .current).uppercased().utf16.first {
                                    indexHeader = c
                                } else if let c = first.folding(options: .diacriticInsensitive, locale: .current).uppercased().utf16.first {
                                    indexHeader = c
                                }
                        }
                }
                if let scalar = UnicodeScalar(indexHeader) {
                    if !NSCharacterSet.uppercaseLetters.contains(scalar) {
                        indexHeader = hashHeader
                        startsWithOther.append(peer)
                    } else {
                        startsWithLetter.append(peer)
                    }
                } else {
                    indexHeader = hashHeader
                    startsWithOther.append(peer)
                }
                let header: ContactListNameIndexHeader
                if let cached = headerCache[indexHeader] {
                    header = cached
                } else {
                    header = ContactListNameIndexHeader(theme: theme, letter: indexHeader)
                    headerCache[indexHeader] = header
                }
                headers[peer.id] = header
            }
            for i in 0 ..< options.count {
                entries.append(.option(i, options[i], nil, theme, strings))
            }
            orderedPeers = startsWithLetter + startsWithOther
        case .search:
            orderedPeers = peers
    }
    
    var removeIndices: [Int] = []
    for i in 0 ..< orderedPeers.count {
        switch orderedPeers[i].indexName {
            case let .title(title, _):
                if title.isEmpty {
                    removeIndices.append(i)
                }
            case let .personName(first, last, _, _):
                if first.isEmpty && last.isEmpty {
                    removeIndices.append(i)
                }
        }
    }
    if !removeIndices.isEmpty {
        for index in removeIndices.reversed() {
            orderedPeers.remove(at: index)
        }
    }
    
    for i in 0 ..< orderedPeers.count {
        let selection: ContactsPeerItemSelection
        if let selectionState = selectionState {
            selection = .selectable(selected: selectionState.selectedPeerIndices[orderedPeers[i].id] != nil)
        } else {
            selection = .none
        }
        let header: ListViewItemHeader?
        switch presentation {
            case .orderedByPresence:
                header = commonHeader
            default:
                header = headers[orderedPeers[i].id]
        }
        var presence: PeerPresence?
        if case let .peer(peer, _) = orderedPeers[i] {
            presence = presences[peer.id]
        }
        let enabled: Bool
        switch orderedPeers[i] {
            case let .peer(peer, _):
                enabled = !disabledPeerIds.contains(peer.id)
            default:
                enabled = true
        }
        entries.append(.peer(i, orderedPeers[i], presence, header, selection, theme, strings, dateTimeFormat, sortOrder, displayOrder, enabled))
    }
    return entries
}

private func preparedContactListNodeTransition(account: Account, from fromEntries: [ContactListNodeEntry], to toEntries: [ContactListNodeEntry], interaction: ContactListNodeInteraction, firstTime: Bool, isEmpty: Bool, generateIndexSections: Bool, animation: ContactListAnimation) -> ContactsListNodeTransition {
    let (deleteIndices, indicesAndItems, updateIndices) = mergeListsStableWithUpdates(leftList: fromEntries, rightList: toEntries)
    
    let deletions = deleteIndices.map { ListViewDeleteItem(index: $0, directionHint: nil) }
    let insertions = indicesAndItems.map { ListViewInsertItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(account: account, interaction: interaction), directionHint: nil) }
    let updates = updateIndices.map { ListViewUpdateItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(account: account, interaction: interaction), directionHint: nil) }
    
    var shouldFixScroll = false
    var indexSections: [String] = []
    if generateIndexSections {
        var existingSections = Set<unichar>()
        for entry in toEntries {
            switch entry {
                case .sort:
                    shouldFixScroll = true
                case .search:
                    //indexSections.apend(CollectionIndexNode.searchIndex)
                    break
                case let .peer(_, _, _, header, _, _, _, _, _, _, _):
                    if let header = header as? ContactListNameIndexHeader {
                        if !existingSections.contains(header.letter) {
                            existingSections.insert(header.letter)
                            if let scalar = UnicodeScalar(header.letter) {
                                let title = "\(Character(scalar))"
                                indexSections.append(title)
                            }
                        }
                    }
                default:
                    break
            }
        }
    } else {
        outer: for entry in toEntries {
            switch entry {
                case .sort:
                    shouldFixScroll = true
                    break outer
                default:
                    break
            }
        }
    }
    
    var scrollToItem: ListViewScrollToItem?
    if firstTime && shouldFixScroll && toEntries.count >= 1 {
        scrollToItem = ListViewScrollToItem(index: 0, position: .top(-50.0), animated: false, curve: .Default(duration: 0.0), directionHint: .Up)
    }
    
    return ContactsListNodeTransition(deletions: deletions, insertions: insertions, updates: updates, indexSections: indexSections, firstTime: firstTime, isEmpty: isEmpty, scrollToItem: scrollToItem, animation: animation)
}

private struct ContactsListNodeTransition {
    let deletions: [ListViewDeleteItem]
    let insertions: [ListViewInsertItem]
    let updates: [ListViewUpdateItem]
    let indexSections: [String]
    let firstTime: Bool
    let isEmpty: Bool
    let scrollToItem: ListViewScrollToItem?
    let animation: ContactListAnimation
}

public struct ContactListAdditionalOption: Equatable {
    public let title: String
    public let icon: ContactListActionItemIcon
    public let action: () -> Void
    
    public static func ==(lhs: ContactListAdditionalOption, rhs: ContactListAdditionalOption) -> Bool {
        return lhs.title == rhs.title && lhs.icon == rhs.icon
    }
}

enum ContactListPresentation {
    case orderedByPresence(options: [ContactListAdditionalOption])
    case natural(options: [ContactListAdditionalOption])
    case search(signal: Signal<String, NoError>, searchChatList: Bool, searchDeviceContacts: Bool)
    
    var sortOrder: ContactsSortOrder? {
        switch self {
            case .orderedByPresence:
                return .presence
            case .natural:
                return .natural
            default:
                return nil
        }
    }
}

struct ContactListNodeGroupSelectionState: Equatable {
    let selectedPeerIndices: [ContactListPeerId: Int]
    let nextSelectionIndex: Int
    
    private init(selectedPeerIndices: [ContactListPeerId: Int], nextSelectionIndex: Int) {
        self.selectedPeerIndices = selectedPeerIndices
        self.nextSelectionIndex = nextSelectionIndex
    }
    
    init() {
        self.selectedPeerIndices = [:]
        self.nextSelectionIndex = 0
    }
    
    func withToggledPeerId(_ peerId: ContactListPeerId) -> ContactListNodeGroupSelectionState {
        var updatedIndices = self.selectedPeerIndices
        if let _ = updatedIndices[peerId] {
            updatedIndices.removeValue(forKey: peerId)
            return ContactListNodeGroupSelectionState(selectedPeerIndices: updatedIndices, nextSelectionIndex: self.nextSelectionIndex)
        } else {
            updatedIndices[peerId] = self.nextSelectionIndex
            return ContactListNodeGroupSelectionState(selectedPeerIndices: updatedIndices, nextSelectionIndex: self.nextSelectionIndex + 1)
        }
    }
}

enum ContactListFilter {
    case excludeSelf
    case exclude([PeerId])
    case disable([PeerId])
}

final class ContactListNode: ASDisplayNode {
    private let context: AccountContext
    private var presentation: ContactListPresentation?
    private let filters: [ContactListFilter]
    
    let listNode: ListView
    private var indexNode: CollectionIndexNode
    private var indexSections: [String]?
    
    private var queuedTransitions: [ContactsListNodeTransition] = []
    private var validLayout: (ContainerViewLayout, UIEdgeInsets)?
    
    private var _ready = ValuePromise<Bool>()
    var ready: Signal<Bool, NoError> {
        return self._ready.get()
    }
    private var didSetReady = false
    
    private let contactPeersViewPromise = Promise<ContactPeersView>()
    
    private let selectionStatePromise = Promise<ContactListNodeGroupSelectionState?>(nil)
    private var selectionStateValue: ContactListNodeGroupSelectionState? {
        didSet {
            self.selectionStatePromise.set(.single(self.selectionStateValue))
        }
    }
    var selectionState: ContactListNodeGroupSelectionState? {
        return self.selectionStateValue
    }
    
    private var enableUpdatesValue = false
    var enableUpdates: Bool {
        get {
            return self.enableUpdatesValue
        } set(value) {
            if value != self.enableUpdatesValue {
                self.enableUpdatesValue = value
                if value {
                    self.contactPeersViewPromise.set(self.context.account.postbox.contactPeersView(accountPeerId: self.context.account.peerId, includePresences: true) |> mapToThrottled { next -> Signal<ContactPeersView, NoError> in
                        return .single(next) |> then(.complete() |> delay(5.0, queue: Queue.concurrentDefaultQueue()))
                    })
                } else {
                    self.contactPeersViewPromise.set(self.context.account.postbox.contactPeersView(accountPeerId: self.context.account.peerId, includePresences: true) |> take(1))
                }
            }
        }
    }
    
    var contentOffsetChanged: ((ListViewVisibleContentOffset) -> Void)?
    var contentScrollingEnded: ((ListView) -> Bool)?
    
    var activateSearch: (() -> Void)?
    var openSortMenu: (() -> Void)?
    var openPeer: ((ContactListPeer) -> Void)?
    var openPrivacyPolicy: (() -> Void)?
    var suppressPermissionWarning: (() -> Void)?
    
    private let previousEntries = Atomic<[ContactListNodeEntry]?>(value: nil)
    private let disposable = MetaDisposable()
    
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?
    private let themeAndStringsPromise: Promise<(PresentationTheme, PresentationStrings, PresentationDateTimeFormat, PresentationPersonNameOrder, PresentationPersonNameOrder, Bool)>
    
    private var authorizationNode: PermissionContentNode
    private let displayPermissionPlaceholder: Bool
    
    init(context: AccountContext, presentation: Signal<ContactListPresentation, NoError>, filters: [ContactListFilter] = [.excludeSelf], selectionState: ContactListNodeGroupSelectionState? = nil, displayPermissionPlaceholder: Bool = true, displaySortOptions: Bool = false) {
        self.context = context
        self.filters = filters
        self.displayPermissionPlaceholder = displayPermissionPlaceholder
        
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        
        self.listNode = ListView()
        self.listNode.dynamicBounceEnabled = !self.presentationData.disableAnimations
        
        self.indexNode = CollectionIndexNode()
        
        self.themeAndStringsPromise = Promise((self.presentationData.theme, self.presentationData.strings, self.presentationData.dateTimeFormat, self.presentationData.nameSortOrder, self.presentationData.nameDisplayOrder, self.presentationData.disableAnimations))
        
        let contactsAuthorization = Promise<AccessType>()
        contactsAuthorization.set(.single(.allowed)
        |> then(DeviceAccess.authorizationStatus(context: context, subject: .contacts)))
        
        let contactsWarningSuppressed = Promise<(Bool, Bool)>()
        contactsWarningSuppressed.set(.single((false, false))
        |> then(
            combineLatest(context.sharedContext.accountManager.noticeEntry(key: ApplicationSpecificNotice.contactsPermissionWarningKey()), context.account.postbox.preferencesView(keys: [PreferencesKeys.contactsSettings]))
            |> map { noticeView, preferences -> (Bool, Bool) in
                let settings: ContactsSettings = preferences.values[PreferencesKeys.contactsSettings] as? ContactsSettings ?? ContactsSettings.defaultSettings
                let synchronizeDeviceContacts: Bool = settings.synchronizeContacts
                let suppressed: Bool
                let timestamp = noticeView.value.flatMap({ ApplicationSpecificNotice.getTimestampValue($0) })
                if let timestamp = timestamp, timestamp > 0 {
                    suppressed = true
                } else {
                    suppressed = false
                }
                return (suppressed, !synchronizeDeviceContacts)
            }
        ))
        
        var authorizeImpl: (() -> Void)?
        var openPrivacyPolicyImpl: (() -> Void)?
        
        self.authorizationNode = PermissionContentNode(theme: self.presentationData.theme, strings: self.presentationData.strings, kind: .contacts, icon: UIImage(bundleImageName: "Settings/Permissions/Contacts"), title: self.presentationData.strings.Contacts_PermissionsTitle, text: self.presentationData.strings.Contacts_PermissionsText, buttonTitle: self.presentationData.strings.Contacts_PermissionsAllow, buttonAction: {
            authorizeImpl?()
        }, openPrivacyPolicy: {
            openPrivacyPolicyImpl?()
        })
        self.authorizationNode.isHidden = true
        
        super.init()
        
        self.backgroundColor = self.presentationData.theme.chatList.backgroundColor
        self.listNode.verticalScrollIndicatorColor = self.presentationData.theme.list.scrollIndicatorColor
        
        self.selectionStateValue = selectionState
        self.selectionStatePromise.set(.single(selectionState))
        
        self.addSubnode(self.listNode)
        self.addSubnode(self.indexNode)
        self.addSubnode(self.authorizationNode)
        
        let processingQueue = Queue()
        let previousEntries = Atomic<[ContactListNodeEntry]?>(value: nil)
        
        let interaction = ContactListNodeInteraction(activateSearch: { [weak self] in
            self?.activateSearch?()
        }, openSortMenu: { [weak self] in
            self?.openSortMenu?()
        }, authorize: {
            authorizeImpl?()
        }, suppressWarning: { [weak self] in
            self?.suppressPermissionWarning?()
        }, openPeer: { [weak self] peer in
            self?.openPeer?(peer)
        })
        
        self.indexNode.indexSelected = { [weak self] section in
            guard let strongSelf = self, let layout = strongSelf.validLayout, let entries = previousEntries.with({ $0 }) else {
                return
            }
            
            var insets = layout.0.insets(options: [.input])
            insets.left += layout.0.safeInsets.left
            insets.right += layout.0.safeInsets.right
            
            var headerInsets = layout.1
            if headerInsets.top == insets.top {
                headerInsets.top -= navigationBarSearchContentHeight
            }
            
            let updateSizeAndInsets = ListViewUpdateSizeAndInsets(size: layout.0.size, insets: insets, headerInsets: headerInsets, duration: 0.0, curve: .Default(duration: nil))
            
            var index = 0
            var peerIndex = 0
            loop: for entry in entries {
                switch entry {
                    case .search:
                        if section == CollectionIndexNode.searchIndex {
                            strongSelf.listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.PreferSynchronousDrawing, .PreferSynchronousResourceLoading], scrollToItem: ListViewScrollToItem(index: index, position: .top(-navigationBarSearchContentHeight), animated: false, curve: .Default(duration: nil), directionHint: .Down), additionalScrollDistance: 0.0, updateSizeAndInsets: updateSizeAndInsets, stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
                            break loop
                        }
                    case let .peer(_, _, _, header, _, _, _, _, _, _, _):
                        if let header = header as? ContactListNameIndexHeader {
                            if let scalar = UnicodeScalar(header.letter) {
                                let title = "\(Character(scalar))"
                                if title == section {
                                    strongSelf.listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.PreferSynchronousDrawing, .PreferSynchronousResourceLoading], scrollToItem: ListViewScrollToItem(index: peerIndex == 0 ? 0 : index, position: .top(peerIndex == 0 ? 0.0 : -navigationBarSearchContentHeight), animated: false, curve: .Default(duration: nil), directionHint: .Down), additionalScrollDistance: 0.0, updateSizeAndInsets: updateSizeAndInsets, stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
                                    break loop
                                }
                            }
                        }
                        peerIndex += 1
                    default:
                        break
                }
                index += 1
            }
        }
        
        let context = self.context
        var firstTime: Int32 = 1
        let selectionStateSignal = self.selectionStatePromise.get()
        let transition: Signal<ContactsListNodeTransition, NoError>
        let themeAndStringsPromise = self.themeAndStringsPromise
        
        transition = presentation
        |> mapToSignal { presentation in
            var generateSections = false
            if case .natural = presentation {
                generateSections = true
            }
            
            if case let .search(query, searchChatList, searchDeviceContacts) = presentation {
                return query
                |> mapToSignal { query in
                    let foundLocalContacts: Signal<([Peer], [PeerId : PeerPresence]), NoError>
                    if searchChatList {
                        let foundChatListPeers = context.account.postbox.searchPeers(query: query.lowercased(), groupId: nil)
                        foundLocalContacts = foundChatListPeers
                        |> mapToSignal { peers -> Signal<([Peer], [PeerId : PeerPresence]), NoError> in
                            var resultPeers: [Peer] = []
                            for peer in peers {
                                if peer.peerId.namespace != Namespaces.Peer.CloudUser {
                                    continue
                                }
                                if let mainPeer = peer.chatMainPeer {
                                    resultPeers.append(mainPeer)
                                }
                            }
                            return context.account.postbox.transaction { transaction -> ([Peer], [PeerId : PeerPresence]) in
                                var resultPresences: [PeerId: PeerPresence] = [:]
                                for peer in resultPeers {
                                    if let presence = transaction.getPeerPresence(peerId: peer.id) {
                                        resultPresences[peer.id] = presence
                                    }
                                }
                                return (resultPeers, resultPresences)
                            }
                        }
                    } else {
                        foundLocalContacts = context.account.postbox.searchContacts(query: query.lowercased())
                    }
                    let foundRemoteContacts: Signal<([FoundPeer], [FoundPeer]), NoError> = .single(([], []))
                    |> then(
                        searchPeers(account: context.account, query: query)
                        |> map { ($0.0, $0.1) }
                        |> delay(0.2, queue: Queue.concurrentDefaultQueue())
                    )
                    let foundDeviceContacts: Signal<[DeviceContactStableId: DeviceContactBasicData], NoError>
                    if searchDeviceContacts {
                        foundDeviceContacts = context.sharedContext.contactDataManager?.search(query: query) ?? .single([:])
                    } else {
                        foundDeviceContacts = .single([:])
                    }
                    
                    return combineLatest(foundLocalContacts, foundRemoteContacts, foundDeviceContacts, selectionStateSignal, themeAndStringsPromise.get())
                    |> mapToQueue { localPeersAndStatuses, remotePeers, deviceContacts, selectionState, themeAndStrings -> Signal<ContactsListNodeTransition, NoError> in
                        let signal = deferred { () -> Signal<ContactsListNodeTransition, NoError> in
                            var existingPeerIds = Set<PeerId>()
                            var disabledPeerIds = Set<PeerId>()

                            var existingNormalizedPhoneNumbers = Set<DeviceContactNormalizedPhoneNumber>()
                            for filter in filters {
                                switch filter {
                                    case .excludeSelf:
                                        existingPeerIds.insert(context.account.peerId)
                                    case let .exclude(peerIds):
                                        existingPeerIds = existingPeerIds.union(peerIds)
                                    case let .disable(peerIds):
                                        disabledPeerIds = disabledPeerIds.union(peerIds)
                                }
                            }
                            
                            var peers: [ContactListPeer] = []
                            for peer in localPeersAndStatuses.0 {
                                if !existingPeerIds.contains(peer.id) {
                                    existingPeerIds.insert(peer.id)
                                    peers.append(.peer(peer: peer, isGlobal: false))
                                    if searchDeviceContacts, let user = peer as? TelegramUser, let phone = user.phone {
                                        existingNormalizedPhoneNumbers.insert(DeviceContactNormalizedPhoneNumber(rawValue: formatPhoneNumber(phone)))
                                    }
                                }
                            }
                            for peer in remotePeers.0 {
                                if peer.peer is TelegramUser {
                                    if !existingPeerIds.contains(peer.peer.id) {
                                        existingPeerIds.insert(peer.peer.id)
                                        peers.append(.peer(peer: peer.peer, isGlobal: true))
                                        if searchDeviceContacts, let user = peer.peer as? TelegramUser, let phone = user.phone {
                                            existingNormalizedPhoneNumbers.insert(DeviceContactNormalizedPhoneNumber(rawValue: formatPhoneNumber(phone)))
                                        }
                                    }
                                }
                            }
                            for peer in remotePeers.1 {
                                if peer.peer is TelegramUser {
                                    if !existingPeerIds.contains(peer.peer.id) {
                                        existingPeerIds.insert(peer.peer.id)
                                        peers.append(.peer(peer: peer.peer, isGlobal: true))
                                        if searchDeviceContacts, let user = peer.peer as? TelegramUser, let phone = user.phone {
                                            existingNormalizedPhoneNumbers.insert(DeviceContactNormalizedPhoneNumber(rawValue: formatPhoneNumber(phone)))
                                        }
                                    }
                                }
                            }
                            
                            outer: for (stableId, contact) in deviceContacts {
                                inner: for phoneNumber in contact.phoneNumbers {
                                    let normalizedNumber = DeviceContactNormalizedPhoneNumber(rawValue: formatPhoneNumber(phoneNumber.value))
                                    if existingNormalizedPhoneNumbers.contains(normalizedNumber) {
                                        continue outer
                                    }
                                }
                                peers.append(.deviceContact(stableId, contact))
                            }
                            
                            let entries = contactListNodeEntries(accountPeer: nil, peers: peers, presences: localPeersAndStatuses.1, presentation: presentation, selectionState: selectionState, theme: themeAndStrings.0, strings: themeAndStrings.1, dateTimeFormat: themeAndStrings.2, sortOrder: themeAndStrings.3, displayOrder: themeAndStrings.4, disabledPeerIds: disabledPeerIds, authorizationStatus: .allowed, warningSuppressed: (true, true), displaySortOptions: false)
                            let previous = previousEntries.swap(entries)
                            return .single(preparedContactListNodeTransition(account: context.account, from: previous ?? [], to: entries, interaction: interaction, firstTime: previous == nil, isEmpty: false, generateIndexSections: generateSections, animation: .none))
                        }
                        
                        if OSAtomicCompareAndSwap32(1, 0, &firstTime) {
                            return signal |> runOn(Queue.mainQueue())
                        } else {
                            return signal |> runOn(processingQueue)
                        }
                    }
                }
            } else {
                return (combineLatest(self.contactPeersViewPromise.get(), selectionStateSignal, themeAndStringsPromise.get(), contactsAuthorization.get(), contactsWarningSuppressed.get())
                |> mapToQueue { view, selectionState, themeAndStrings, authorizationStatus, warningSuppressed -> Signal<ContactsListNodeTransition, NoError> in
                    let signal = deferred { () -> Signal<ContactsListNodeTransition, NoError> in
                        var peers = view.peers.map({ ContactListPeer.peer(peer: $0, isGlobal: false) })
                        var existingPeerIds = Set<PeerId>()
                        var disabledPeerIds = Set<PeerId>()
                        for filter in filters {
                            switch filter {
                                case .excludeSelf:
                                    existingPeerIds.insert(context.account.peerId)
                                case let .exclude(peerIds):
                                    existingPeerIds = existingPeerIds.union(peerIds)
                                case let .disable(peerIds):
                                    disabledPeerIds = disabledPeerIds.union(peerIds)
                            }
                        }
                        
                        peers = peers.filter { contact in
                            switch contact {
                                case let .peer(peer, _):
                                    return !existingPeerIds.contains(peer.id)
                                default:
                                    return true
                            }
                        }
                        
                        var isEmpty = false
                        if (authorizationStatus == .notDetermined || authorizationStatus == .denied) && peers.isEmpty {
                            isEmpty = true
                        }
                        let entries = contactListNodeEntries(accountPeer: view.accountPeer, peers: peers, presences: view.peerPresences, presentation: presentation, selectionState: selectionState, theme: themeAndStrings.0, strings: themeAndStrings.1, dateTimeFormat: themeAndStrings.2, sortOrder: themeAndStrings.3, displayOrder: themeAndStrings.4, disabledPeerIds: disabledPeerIds, authorizationStatus: authorizationStatus, warningSuppressed: warningSuppressed, displaySortOptions: displaySortOptions)
                        let previous = previousEntries.swap(entries)
                        
                        var hadPermissionInfo = false
                        if let previous = previous {
                            for entry in previous {
                                if case .permissionInfo = entry {
                                    hadPermissionInfo = true
                                    break
                                }
                            }
                        }
                        var hasPermissionInfo = false
                        for entry in entries {
                            if case .permissionInfo = entry {
                                hasPermissionInfo = true
                                break
                            }
                        }
                        
                        let animation: ContactListAnimation
                        if hadPermissionInfo != hasPermissionInfo {
                            animation = .insertion
                        }
                        else if let previous = previous, !themeAndStrings.5, (entries.count - previous.count) < 20 {
                            animation = .default
                        } else {
                            animation = .none
                        }
                        
                        return .single(preparedContactListNodeTransition(account: context.account, from: previous ?? [], to: entries, interaction: interaction, firstTime: previous == nil, isEmpty: isEmpty, generateIndexSections: generateSections, animation: animation))
                    }
            
                    if OSAtomicCompareAndSwap32(1, 0, &firstTime) {
                        return signal |> runOn(Queue.mainQueue())
                    } else {
                        return signal |> runOn(processingQueue)
                    }
                })
                |> deliverOnMainQueue
            }
        }
        self.disposable.set(transition.start(next: { [weak self] transition in
            self?.enqueueTransition(transition)
        }))
        
        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            if let strongSelf = self {
                let previousTheme = strongSelf.presentationData.theme
                let previousStrings = strongSelf.presentationData.strings
                let previousDisableAnimations = strongSelf.presentationData.disableAnimations
                
                strongSelf.presentationData = presentationData
                
                if previousTheme !== presentationData.theme || previousStrings !== presentationData.strings || previousDisableAnimations != presentationData.disableAnimations {
                    strongSelf.backgroundColor = presentationData.theme.chatList.backgroundColor
                    strongSelf.listNode.verticalScrollIndicatorColor = presentationData.theme.list.scrollIndicatorColor
                    strongSelf.themeAndStringsPromise.set(.single((presentationData.theme, presentationData.strings, presentationData.dateTimeFormat, presentationData.nameSortOrder, presentationData.nameDisplayOrder, presentationData.disableAnimations)))
                    
                    let authorizationPreviousHidden = strongSelf.authorizationNode.isHidden
                    strongSelf.authorizationNode.removeFromSupernode()
                    strongSelf.authorizationNode = PermissionContentNode(theme: strongSelf.presentationData.theme, strings: strongSelf.presentationData.strings, kind: .contacts, icon: UIImage(bundleImageName: "Settings/Permissions/Contacts"), title: strongSelf.presentationData.strings.Contacts_PermissionsTitle, text: strongSelf.presentationData.strings.Contacts_PermissionsText, buttonTitle: strongSelf.presentationData.strings.Contacts_PermissionsAllow, buttonAction: {
                        authorizeImpl?()
                    }, openPrivacyPolicy: {
                        openPrivacyPolicyImpl?()
                    })
                    strongSelf.authorizationNode.isHidden = authorizationPreviousHidden
                    strongSelf.addSubnode(strongSelf.authorizationNode)
                    
                    strongSelf.listNode.dynamicBounceEnabled = !presentationData.disableAnimations
                    
                    strongSelf.listNode.forEachAccessoryItemNode({ accessoryItemNode in
                        if let accessoryItemNode = accessoryItemNode as? ContactsSectionHeaderAccessoryItemNode {
                            accessoryItemNode.updateTheme(theme: presentationData.theme)
                        }
                    })
                    
                    strongSelf.listNode.forEachItemHeaderNode({ itemHeaderNode in
                        if let itemHeaderNode = itemHeaderNode as? ContactListNameIndexHeaderNode {
                            itemHeaderNode.updateTheme(theme: presentationData.theme)
                        } else if let itemHeaderNode = itemHeaderNode as? ChatListSearchItemHeaderNode {
                            itemHeaderNode.updateTheme(theme: presentationData.theme)
                        }
                    })
                    
                    if let (validLayout, headerInsets) = strongSelf.validLayout {
                        strongSelf.containerLayoutUpdated(validLayout, headerInsets: headerInsets, transition: .immediate)
                    }
                }
            }
        })
        
        self.listNode.didEndScrolling = { [weak self] in
            if let strongSelf = self {
                let _ = strongSelf.contentScrollingEnded?(strongSelf.listNode)
            }
        }
        
        self.listNode.visibleContentOffsetChanged = { [weak self] offset in
            if let strongSelf = self {
                strongSelf.contentOffsetChanged?(offset)
            }
        }
        
        authorizeImpl = {
            let _ = (DeviceAccess.authorizationStatus(context: context, subject: .contacts)
            |> take(1)
            |> deliverOnMainQueue).start(next: { status in
                switch status {
                    case .notDetermined:
                        DeviceAccess.authorizeAccess(to: .contacts, context: context)
                    case .denied, .restricted:
                        context.sharedContext.applicationBindings.openSettings()
                    default:
                        break
                }
            })
        }
        
        openPrivacyPolicyImpl = { [weak self] in
            self?.openPrivacyPolicy?()
        }
        
        self.enableUpdates = true
    }
    
    deinit {
        self.disposable.dispose()
        self.presentationDataDisposable?.dispose()
    }
    
    func updateSelectionState(_ f: (ContactListNodeGroupSelectionState?) -> ContactListNodeGroupSelectionState?) {
        let updatedSelectionState = f(self.selectionStateValue)
        if updatedSelectionState != self.selectionStateValue {
            self.selectionStateValue = updatedSelectionState
        }
    }
    
    func containerLayoutUpdated(_ layout: ContainerViewLayout, headerInsets: UIEdgeInsets, transition: ContainedViewLayoutTransition) {
        let hadValidLayout = self.validLayout != nil
        self.validLayout = (layout, headerInsets)
        
        var insets = layout.insets(options: [.input])
        insets.left += layout.safeInsets.left
        insets.right += layout.safeInsets.right
        
        var headerInsets = headerInsets
        if !hadValidLayout {
            headerInsets.top -= navigationBarSearchContentHeight
        }
        
        self.listNode.bounds = CGRect(x: 0.0, y: 0.0, width: layout.size.width, height: layout.size.height)
        self.listNode.position = CGPoint(x: layout.size.width / 2.0, y: layout.size.height / 2.0)
        
        var duration: Double = 0.0
        var curve: UInt = 0
        switch transition {
            case .immediate:
                break
            case let .animated(animationDuration, animationCurve):
                duration = animationDuration
                switch animationCurve {
                    case .easeInOut:
                        break
                    case .spring:
                        curve = 7
                }
        }
        
        let listViewCurve: ListViewAnimationCurve
        if curve == 7 {
            listViewCurve = .Spring(duration: duration)
        } else {
            listViewCurve = .Default(duration: duration)
        }
        
        let updateSizeAndInsets = ListViewUpdateSizeAndInsets(size: layout.size, insets: insets, headerInsets: headerInsets, duration: duration, curve: listViewCurve)
        
        self.listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous, .LowLatency], scrollToItem: nil, updateSizeAndInsets: updateSizeAndInsets, stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
        if let indexSections = self.indexSections {
            var insets = layout.insets(options: [.input])
            if let inputHeight = layout.inputHeight {
                insets.bottom -= inputHeight
            }
            insets.left += layout.safeInsets.left
            insets.right += layout.safeInsets.right
            
            let indexNodeFrame = CGRect(origin: CGPoint(x: layout.size.width - insets.right - 20.0, y: insets.top), size: CGSize(width: 20.0, height: layout.size.height - insets.top - insets.bottom))
            transition.updateFrame(node: indexNode, frame: indexNodeFrame)
            self.indexNode.update(size: indexNodeFrame.size, color: self.presentationData.theme.list.itemAccentColor, sections: indexSections, transition: transition)
        }
        
        self.authorizationNode.updateLayout(size: layout.size, insets: insets, transition: transition)
        transition.updateFrame(node: self.authorizationNode, frame: self.bounds)
            
        if !hadValidLayout {
            self.dequeueTransitions()
        }
    }
    
    private func enqueueTransition(_ transition: ContactsListNodeTransition) {
        self.queuedTransitions.append(transition)
        
        if self.validLayout != nil {
            self.dequeueTransitions()
        }
    }
    
    private func dequeueTransitions() {
        if self.validLayout != nil {
            while !self.queuedTransitions.isEmpty {
                let transition = self.queuedTransitions.removeFirst()
                
                var options = ListViewDeleteAndInsertOptions()
                if transition.firstTime {
                    options.insert(.Synchronous)
                    options.insert(.LowLatency)
                } else if transition.animation != .none {
                    if transition.animation == .insertion {
                        options.insert(.AnimateInsertion)
                    } else if let presentation = self.presentation, case .orderedByPresence = presentation {
                        options.insert(.AnimateCrossfade)
                    }
                }
                if let (layout, _) = self.validLayout {
                    self.indexSections = transition.indexSections
                    
                    var insets = layout.insets(options: [.input])
                    insets.left += layout.safeInsets.left
                    insets.right += layout.safeInsets.right
                    
                    if let inputHeight = layout.inputHeight {
                        insets.bottom -= inputHeight
                    }
                    
                    let indexNodeFrame = CGRect(origin: CGPoint(x: layout.size.width - insets.right - 20.0, y: insets.top), size: CGSize(width: 20.0, height: layout.size.height - insets.top - insets.bottom))
                    self.indexNode.frame = indexNodeFrame

                    self.indexNode.update(size: CGSize(width: 20.0, height: layout.size.height - insets.top - insets.bottom), color: self.presentationData.theme.list.itemAccentColor, sections: transition.indexSections, transition: .animated(duration: 0.2, curve: .easeInOut))
                }
                
                self.listNode.transaction(deleteIndices: transition.deletions, insertIndicesAndItems: transition.insertions, updateIndicesAndItems: transition.updates, options: options, scrollToItem: transition.scrollToItem, updateOpaqueState: nil, completion: { [weak self] _ in
                    if let strongSelf = self {
                        if !strongSelf.didSetReady {
                            strongSelf.didSetReady = true
                            strongSelf._ready.set(true)
                        }
                    }
                })
                
                self.listNode.isHidden = self.displayPermissionPlaceholder && transition.isEmpty
                self.authorizationNode.isHidden = !transition.isEmpty || !self.displayPermissionPlaceholder
            }
        }
    }
    
    func scrollToTop() {
        self.listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous, .LowLatency], scrollToItem: ListViewScrollToItem(index: 0, position: .top(0.0), animated: true, curve: .Default(duration: nil), directionHint: .Up), updateSizeAndInsets: nil, stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
    }
}
