import Foundation
import Display
import AsyncDisplayKit
import Postbox
import TelegramCore
import SwiftSignalKit

private final class NotificationExceptionState : Equatable {
    let mode:NotificationExceptionMode
    let isSearchMode: Bool
    let revealedPeerId: PeerId?
    let editing: Bool
    
    init(mode: NotificationExceptionMode, isSearchMode: Bool = false, revealedPeerId: PeerId? = nil, editing: Bool = false) {
        self.mode = mode
        self.isSearchMode = isSearchMode
        self.revealedPeerId = revealedPeerId
        self.editing = editing
    }
    
    func withUpdatedMode(_ mode: NotificationExceptionMode) -> NotificationExceptionState {
        return NotificationExceptionState(mode: mode, isSearchMode: self.isSearchMode, revealedPeerId: self.revealedPeerId, editing: self.editing)
    }
    
    func withUpdatedSearchMode(_ isSearchMode: Bool) -> NotificationExceptionState {
        return NotificationExceptionState(mode: self.mode, isSearchMode: isSearchMode, revealedPeerId: self.revealedPeerId, editing: self.editing)
    }
    
    func withUpdatedEditing(_ editing: Bool) -> NotificationExceptionState {
        return NotificationExceptionState(mode: self.mode, isSearchMode: self.isSearchMode, revealedPeerId: self.revealedPeerId, editing: editing)
    }
    
    func withUpdatedRevealedPeerId(_ revealedPeerId: PeerId?) -> NotificationExceptionState {
        return NotificationExceptionState(mode: self.mode, isSearchMode: self.isSearchMode, revealedPeerId: revealedPeerId, editing: self.editing)
    }
    
    func withUpdatedPeerSound(_ peer: Peer, _ sound: PeerMessageSound) -> NotificationExceptionState {
        return NotificationExceptionState(mode: mode.withUpdatedPeerSound(peer, sound), isSearchMode: isSearchMode, revealedPeerId: self.revealedPeerId, editing: self.editing)
    }
    
    func withUpdatedPeerMuteInterval(_ peer: Peer, _ muteInterval: Int32?) -> NotificationExceptionState {
        return NotificationExceptionState(mode: mode.withUpdatedPeerMuteInterval(peer, muteInterval), isSearchMode: isSearchMode, revealedPeerId: self.revealedPeerId, editing: self.editing)
    }
    
    static func == (lhs: NotificationExceptionState, rhs: NotificationExceptionState) -> Bool {
        return lhs.mode == rhs.mode && lhs.isSearchMode == rhs.isSearchMode && lhs.revealedPeerId == rhs.revealedPeerId && lhs.editing == rhs.editing
    }
}

public struct NotificationExceptionWrapper : Equatable {
    let settings: TelegramPeerNotificationSettings
    let date: TimeInterval?
    let peer: Peer
    init(settings: TelegramPeerNotificationSettings, peer: Peer, date: TimeInterval? = nil) {
        self.settings = settings
        self.date = date
        self.peer = peer
    }
    
    public static func ==(lhs: NotificationExceptionWrapper, rhs: NotificationExceptionWrapper) -> Bool {
        return lhs.settings == rhs.settings && lhs.date == rhs.date
    }
    
    func withUpdatedSettings(_ settings: TelegramPeerNotificationSettings) -> NotificationExceptionWrapper {
        return NotificationExceptionWrapper(settings: settings, peer: self.peer, date: self.date)
    }
    
    func updateSettings(_ f: (TelegramPeerNotificationSettings) -> TelegramPeerNotificationSettings) -> NotificationExceptionWrapper {
        return NotificationExceptionWrapper(settings: f(self.settings), peer: self.peer, date: self.date)
    }
    
    
    func withUpdatedDate(_ date: TimeInterval) -> NotificationExceptionWrapper {
        return NotificationExceptionWrapper(settings: self.settings, peer: self.peer, date: date)
    }
}

public enum NotificationExceptionMode : Equatable {
    public static func == (lhs: NotificationExceptionMode, rhs: NotificationExceptionMode) -> Bool {
        switch lhs {
            case let .users(lhsValue):
                if case let .users(rhsValue) = rhs {
                    return lhsValue == rhsValue
                } else {
                    return false
                }
            case let .groups(lhsValue):
                if case let .groups(rhsValue) = rhs {
                    return lhsValue == rhsValue
                } else {
                    return false
                }
            case let .channels(lhsValue):
                if case let .channels(rhsValue) = rhs {
                    return lhsValue == rhsValue
                } else {
                    return false
                }
        }
    }
    
    var isEmpty: Bool {
        switch self {
            case let .users(value), let .groups(value), let .channels(value):
                return value.isEmpty
        }
    }
    
    case users([PeerId : NotificationExceptionWrapper])
    case groups([PeerId : NotificationExceptionWrapper])
    case channels([PeerId : NotificationExceptionWrapper])
    
    func withUpdatedPeerSound(_ peer: Peer, _ sound: PeerMessageSound) -> NotificationExceptionMode {
        let apply:([PeerId : NotificationExceptionWrapper], PeerId, PeerMessageSound) -> [PeerId : NotificationExceptionWrapper] = { values, peerId, sound in
            var values = values
            if let value = values[peerId] {
                switch sound {
                    case .default:
                        switch value.settings.muteState {
                        case .default:
                            values.removeValue(forKey: peerId)
                        default:
                            values[peerId] = value.updateSettings({$0.withUpdatedMessageSound(sound)}).withUpdatedDate(Date().timeIntervalSince1970)
                        }
                    default:
                        values[peerId] = value.updateSettings({$0.withUpdatedMessageSound(sound)}).withUpdatedDate(Date().timeIntervalSince1970)
                }
            } else {
                switch sound {
                    case .default:
                        break
                    default:
                        values[peerId] = NotificationExceptionWrapper(settings: TelegramPeerNotificationSettings(muteState: .default, messageSound: sound), peer: peer, date: Date().timeIntervalSince1970)
                }
            }
            return values
        }
        
        switch self {
            case let .groups(values):
                return .groups(apply(values, peer.id, sound))
            case let .users(values):
                return .users(apply(values, peer.id, sound))
            case let .channels(values):
                return .channels(apply(values, peer.id, sound))
        }
    }
    
    func withUpdatedPeerMuteInterval(_ peer: Peer, _ muteInterval: Int32?) -> NotificationExceptionMode {
        let apply:([PeerId : NotificationExceptionWrapper], PeerId, PeerMuteState) -> [PeerId : NotificationExceptionWrapper] = { values, peerId, muteState in
            var values = values
            if let value = values[peerId] {
                switch muteState {
                    case .default:
                        switch value.settings.messageSound {
                            case .default:
                                values.removeValue(forKey: peerId)
                            default:
                                values[peerId] = value.updateSettings({$0.withUpdatedMuteState(muteState)}).withUpdatedDate(Date().timeIntervalSince1970)
                        }
                    default:
                        values[peerId] = value.updateSettings({$0.withUpdatedMuteState(muteState)}).withUpdatedDate(Date().timeIntervalSince1970)
                }
            } else {
                switch muteState {
                    case .default:
                        break
                    default:
                        values[peerId] = NotificationExceptionWrapper(settings: TelegramPeerNotificationSettings(muteState: muteState, messageSound: .default), peer: peer, date: Date().timeIntervalSince1970)
                }
            }
            return values
        }
        
        let muteState: PeerMuteState
        if let muteInterval = muteInterval {
            if muteInterval == 0 {
                muteState = .unmuted
            } else {
                let absoluteUntil: Int32
                if muteInterval == Int32.max {
                    absoluteUntil = Int32.max
                } else {
                    absoluteUntil = muteInterval
                }
                muteState = .muted(until: absoluteUntil)
            }
        } else {
            muteState = .default
        }
        switch self {
            case let .groups(values):
                return .groups(apply(values, peer.id, muteState))
            case let .users(values):
                return .users(apply(values, peer.id, muteState))
            case let .channels(values):
                return .channels(apply(values, peer.id, muteState))
        }
    }
    
    var peerIds: [PeerId] {
        switch self {
        case let .users(settings), let .groups(settings), let .channels(settings):
            return settings.map {$0.key}
        }
    }
    
    var settings: [PeerId : NotificationExceptionWrapper] {
        switch self {
        case let .users(settings), let .groups(settings), let .channels(settings):
            return settings
        }
    }
}

private func notificationsExceptionEntries(presentationData: PresentationData, state: NotificationExceptionState, query: String? = nil) -> [NotificationExceptionEntry] {
    var entries: [NotificationExceptionEntry] = []
    
    if !state.isSearchMode {
        entries.append(.addException(presentationData.theme, presentationData.strings, state.editing))
    }
    
    var index: Int = 0
    for (_, value) in state.mode.settings.filter({ (_, value) in
        if let query = query, !query.isEmpty {
            return !value.peer.displayTitle.lowercased().components(separatedBy: " ").filter { $0.hasPrefix(query.lowercased())}.isEmpty
        } else {
            return true
        }
    }).sorted(by: { lhs, rhs in
        let lhsName = lhs.value.peer.displayTitle
        let rhsName = rhs.value.peer.displayTitle
        
        if let lhsDate = lhs.value.date, let rhsDate = rhs.value.date {
            return lhsDate > rhsDate
        } else if lhs.value.date != nil && rhs.value.date == nil {
            return true
        } else if lhs.value.date == nil && rhs.value.date != nil {
            return false
        }
        
        if let lhsPeer = lhs.value.peer as? TelegramUser, let rhsPeer = rhs.value.peer as? TelegramUser {
            if lhsPeer.botInfo != nil && rhsPeer.botInfo == nil {
                return false
            } else if lhsPeer.botInfo == nil && rhsPeer.botInfo != nil {
                return true
            }
        }
        
        return lhsName < rhsName
    }) {
        if !value.peer.displayTitle.isEmpty {
            var title: String
            switch value.settings.muteState {
                case let .muted(until):
                    if until >= Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970) {
                        if until < Int32.max - 1 {
                            let formatter = DateFormatter()
                            formatter.locale = Locale(identifier: presentationData.strings.baseLanguageCode)
                            
                            if Calendar.current.isDateInToday(Date(timeIntervalSince1970: Double(until))) {
                                formatter.dateFormat = "HH:mm"
                            } else {
                                formatter.dateFormat = "E, d MMM HH:mm"
                            }
                            
                            let dateString = formatter.string(from: Date(timeIntervalSince1970: Double(until)))
                            
                            title = presentationData.strings.Notification_Exceptions_MutedUntil(dateString).0
                        } else {
                            title = presentationData.strings.Notification_Exceptions_AlwaysOff
                        }
                    } else {
                        title = presentationData.strings.Notification_Exceptions_AlwaysOn
                    }
                case .unmuted:
                    title = presentationData.strings.Notification_Exceptions_AlwaysOn
                default:
                    title = ""
            }
            switch value.settings.messageSound {
                case .default:
                    break
                default:
                    let soundName = localizedPeerNotificationSoundString(strings: presentationData.strings, sound: value.settings.messageSound)
                    title += (title.isEmpty ? presentationData.strings.Notification_Exceptions_Sound(soundName).0 : ", \(presentationData.strings.Notification_Exceptions_Sound(soundName).0)")
            }
            entries.append(.peer(index: index, peer: value.peer, theme: presentationData.theme, strings: presentationData.strings, dateFormat: presentationData.dateTimeFormat, nameDisplayOrder: presentationData.nameDisplayOrder, description: title, notificationSettings: value.settings, revealed: state.revealedPeerId == value.peer.id, editing: state.editing))
            index += 1
        }
    }
    
    return entries
}

private final class NotificationExceptionArguments {
    let account: Account
    let activateSearch:()->Void
    let openPeer: (Peer) -> Void
    let selectPeer: ()->Void
    let updateRevealedPeerId:(PeerId?)->Void
    let deletePeer:(Peer) -> Void
    
    init(account: Account, activateSearch:@escaping() -> Void, openPeer: @escaping(Peer) -> Void, selectPeer: @escaping()->Void, updateRevealedPeerId:@escaping(PeerId?)->Void, deletePeer: @escaping(Peer) -> Void) {
        self.account = account
        self.activateSearch = activateSearch
        self.openPeer = openPeer
        self.selectPeer = selectPeer
        self.updateRevealedPeerId = updateRevealedPeerId
        self.deletePeer = deletePeer
    }
}

private enum NotificationExceptionEntryId: Hashable {
    case search
    case peerId(Int64)
    case addException
    
    var hashValue: Int {
        switch self {
            case .search:
                return 0
            case .addException:
                return 1
            case let .peerId(peerId):
                return peerId.hashValue
        }
    }
    
    static func <(lhs: NotificationExceptionEntryId, rhs: NotificationExceptionEntryId) -> Bool {
        return lhs.hashValue < rhs.hashValue
    }
    
    static func ==(lhs: NotificationExceptionEntryId, rhs: NotificationExceptionEntryId) -> Bool {
        switch lhs {
            case .search:
                switch rhs {
                    case .search:
                        return true
                    default:
                        return false
                }
            case .addException:
                switch rhs {
                    case .addException:
                        return true
                    default:
                        return false
                }
            case let .peerId(lhsId):
                switch rhs {
                    case let .peerId(rhsId):
                        return lhsId == rhsId
                    default:
                        return false
                }
        }
    }
}

private enum NotificationExceptionSectionId : ItemListSectionId {
    case general = 0
}

private enum NotificationExceptionEntry : ItemListNodeEntry {
    var section: ItemListSectionId {
        return NotificationExceptionSectionId.general.rawValue
    }
    
    typealias ItemGenerationArguments = NotificationExceptionArguments
    
    case search(PresentationTheme, PresentationStrings)
    case peer(index: Int, peer: Peer, theme: PresentationTheme, strings: PresentationStrings, dateFormat: PresentationDateTimeFormat, nameDisplayOrder: PresentationPersonNameOrder, description: String, notificationSettings: TelegramPeerNotificationSettings, revealed: Bool, editing: Bool)
    case addException(PresentationTheme, PresentationStrings, Bool)
    
    func item(_ arguments: NotificationExceptionArguments) -> ListViewItem {
        switch self {
            case let .search(theme, strings):
                return NotificationSearchItem(theme: theme, placeholder: strings.Common_Search, activate: {
                    arguments.activateSearch()
                })
            case let .addException(theme, strings, editing):
                return ItemListPeerActionItem(theme: theme, icon: PresentationResourcesItemList.addExceptionIcon(theme), title: strings.Notification_Exceptions_AddException, alwaysPlain: true, sectionId: self.section, editing: editing, action: {
                    arguments.selectPeer()
                })
            case let .peer(_, peer, theme, strings, dateTimeFormat, nameDisplayOrder, value, _, revealed, editing):
                return ItemListPeerItem(theme: theme, strings: strings, dateTimeFormat: dateTimeFormat, nameDisplayOrder: nameDisplayOrder, account: arguments.account, peer: peer, presence: nil, text: .text(value), label: .none, editing: ItemListPeerItemEditing(editable: true, editing: editing, revealed: revealed), switchValue: nil, enabled: true, sectionId: self.section, action: {
                    arguments.openPeer(peer)
                }, setPeerIdWithRevealedOptions: { peerId, fromPeerId in
                    arguments.updateRevealedPeerId(peerId)
                }, removePeer: { peerId in
                    arguments.deletePeer(peer)
                }, hasTopStripe: false, hasTopGroupInset: false)
        }
    }
    
    var stableId: NotificationExceptionEntryId {
        switch self {
            case .search:
                return .search
            case .addException:
                return .addException
            case let .peer(_, peer, _, _, _, _, _, _, _, _):
                return .peerId(peer.id.toInt64())
        }
    }
    
    static func == (lhs: NotificationExceptionEntry, rhs: NotificationExceptionEntry) -> Bool {
        switch lhs {
            case let .search(lhsTheme, lhsStrings):
                switch rhs {
                    case let .search(rhsTheme, rhsStrings):
                        return lhsTheme === rhsTheme && lhsStrings === rhsStrings
                    default:
                        return false
                }
            case let .addException(lhsTheme, lhsStrings, lhsEditing):
                switch rhs {
                    case let .addException(rhsTheme, rhsStrings, rhsEditing):
                        return lhsTheme === rhsTheme && lhsStrings === rhsStrings && lhsEditing == rhsEditing
                    default:
                        return false
                }
            case let .peer(lhsIndex, lhsPeer, lhsTheme, lhsStrings, lhsDateTimeFormat, lhsNameOrder, lhsValue, lhsSettings, lhsRevealed, lhsEditing):
                switch rhs {
                    case let .peer(rhsIndex, rhsPeer, rhsTheme, rhsStrings, rhsDateTimeFormat, rhsNameOrder, rhsValue, rhsSettings, rhsRevealed, rhsEditing):
                        return lhsTheme === rhsTheme && lhsStrings === rhsStrings && lhsDateTimeFormat == rhsDateTimeFormat && lhsNameOrder == rhsNameOrder && lhsIndex == rhsIndex && lhsPeer.isEqual(rhsPeer) && lhsValue == rhsValue && lhsSettings == rhsSettings && lhsRevealed == rhsRevealed && lhsEditing == rhsEditing
                    default:
                        return false
                }
        }
    }
    
    static func <(lhs: NotificationExceptionEntry, rhs: NotificationExceptionEntry) -> Bool {
        switch lhs {
            case .search:
                return true
            case .addException:
                switch rhs {
                    case .search, .addException:
                        return false
                    default:
                        return true
                }
            case let .peer(lhsIndex, _, _, _, _, _, _, _, _, _):
                switch rhs {
                    case .search, .addException:
                        return false
                    case let .peer(rhsIndex, _, _, _, _, _, _, _, _, _):
                        return lhsIndex < rhsIndex
                }
        }
    }
}

private struct NotificationExceptionNodeTransition {
    let deletions: [ListViewDeleteItem]
    let insertions: [ListViewInsertItem]
    let updates: [ListViewUpdateItem]
    let firstTime: Bool
    let animated: Bool
}

private func preparedExceptionsListNodeTransition(theme: PresentationTheme, strings: PresentationStrings, from fromEntries: [NotificationExceptionEntry], to toEntries: [NotificationExceptionEntry], arguments: NotificationExceptionArguments, firstTime: Bool, forceUpdate: Bool, animated: Bool) -> NotificationExceptionNodeTransition {
    let (deleteIndices, indicesAndItems, updateIndices) = mergeListsStableWithUpdates(leftList: fromEntries, rightList: toEntries, allUpdated: forceUpdate)
    
    let deletions = deleteIndices.map { ListViewDeleteItem(index: $0, directionHint: nil) }
    let insertions = indicesAndItems.map { ListViewInsertItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(arguments), directionHint: nil) }
    let updates = updateIndices.map { ListViewUpdateItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(arguments), directionHint: nil) }
    
    return NotificationExceptionNodeTransition(deletions: deletions, insertions: insertions, updates: updates, firstTime: firstTime, animated: animated)
}

private extension PeerMuteState {
    var timeInterval: Int32? {
        switch self {
            case .default:
                return nil
            case .unmuted:
                return 0
            case let .muted(until):
                return until
        }
    }
}

final class NotificationExceptionsControllerNode: ViewControllerTracingNode {
    private let context: AccountContext
    private var presentationData: PresentationData
    private let navigationBar: NavigationBar
    private let requestActivateSearch: () -> Void
    private let requestDeactivateSearch: () -> Void
    private let present: (ViewController, Any?) -> Void
    private let pushController: (ViewController) -> Void
    private var didSetReady = false
    let _ready = ValuePromise<Bool>()
    
    private var containerLayout: (ContainerViewLayout, CGFloat, CGFloat)?
    let listNode: ListView
    private var queuedTransitions: [NotificationExceptionNodeTransition] = []
    
    private var searchDisplayController: SearchDisplayController?
    
    private let presentationDataValue = Promise<(PresentationTheme, PresentationStrings)>()
    private var listDisposable: Disposable?
    
    private var arguments: NotificationExceptionArguments?
    private let stateValue: Atomic<NotificationExceptionState>
    private let statePromise: ValuePromise<NotificationExceptionState> = ValuePromise(ignoreRepeated: true)
    private let navigationActionDisposable = MetaDisposable()
    private let updateNotificationsDisposable = MetaDisposable()

    func addPressed() {
        self.arguments?.selectPeer()
    }
    
    init(context: AccountContext, presentationData: PresentationData, navigationBar: NavigationBar, mode: NotificationExceptionMode, updatedMode:@escaping(NotificationExceptionMode)->Void, requestActivateSearch: @escaping () -> Void, requestDeactivateSearch: @escaping () -> Void, updateCanStartEditing: @escaping (Bool?) -> Void, present: @escaping (ViewController, Any?) -> Void, pushController: @escaping (ViewController) -> Void) {
        self.context = context
        self.presentationData = presentationData
        self.presentationDataValue.set(.single((presentationData.theme, presentationData.strings)))
        self.navigationBar = navigationBar
        self.requestActivateSearch = requestActivateSearch
        self.requestDeactivateSearch = requestDeactivateSearch
        self.present = present
        self.pushController = pushController
        self.stateValue = Atomic(value: NotificationExceptionState(mode: mode))
        self.listNode = ListView()
        self.listNode.keepTopItemOverscrollBackground = ListViewKeepTopItemOverscrollBackground(color: presentationData.theme.chatList.backgroundColor, direction: true)
        //self.listNode.keepBottomItemOverscrollBackground = presentationData.theme.chatList.backgroundColor
        super.init()
        
        let stateValue = self.stateValue
        let statePromise = self.statePromise
        statePromise.set(NotificationExceptionState(mode: mode))
        
        let updateState: ((NotificationExceptionState) -> NotificationExceptionState) -> Void = {  f in
            let result = stateValue.modify { f($0) }
            statePromise.set(result)
            updatedMode(result.mode)
        }
        
        let updateNotificationsDisposable = self.updateNotificationsDisposable
        var peerIds: Set<PeerId> = Set(mode.peerIds)
        
        let updateNotificationsView:()->Void = {
            updateState { current in
                peerIds = peerIds.union(current.mode.peerIds)
                let key: PostboxViewKey = .peerNotificationSettings(peerIds: peerIds)
                updateNotificationsDisposable.set((context.account.postbox.combinedView(keys: [key]) |> deliverOnMainQueue).start(next: { view in
                    if let view = view.views[key] as? PeerNotificationSettingsView {
                        _ = context.account.postbox.transaction { transaction in
                            updateState { current in
                                var current = current
                                for (key, value) in view.notificationSettings {
                                    if let value = value as? TelegramPeerNotificationSettings {
                                        if let local = current.mode.settings[key]  {
                                            if !value.isEqual(to: local.settings), let peer = transaction.getPeer(key), let settings = transaction.getPeerNotificationSettings(key) as? TelegramPeerNotificationSettings, !settings.isEqual(to: local.settings) {
                                                current = current.withUpdatedPeerSound(peer, settings.messageSound).withUpdatedPeerMuteInterval(peer, settings.muteState.timeInterval)
                                            }
                                        } else if let peer = transaction.getPeer(key) {
                                            current = current.withUpdatedPeerSound(peer, value.messageSound).withUpdatedPeerMuteInterval(peer, value.muteState.timeInterval)
                                        }
                                    }
                                }
                                return current
                            }
                            }.start()
                        
                    }
                }))
                return current
            }
        }
        
        updateNotificationsView()
        
        var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
        
        let presentationData = context.sharedContext.currentPresentationData.modify {$0}
        
        let updatePeerSound: (PeerId, PeerMessageSound) -> Signal<Void, NoError> = { peerId, sound in
            return updatePeerNotificationSoundInteractive(account: context.account, peerId: peerId, sound: sound) |> deliverOnMainQueue
        }
        
        let updatePeerNotificationInterval:(PeerId, Int32?) -> Signal<Void, NoError> = { peerId, muteInterval in
            return updatePeerMuteSetting(account: context.account, peerId: peerId, muteInterval: muteInterval) |> deliverOnMainQueue
        }
        
        self.backgroundColor = presentationData.theme.list.blocksBackgroundColor
        self.addSubnode(self.listNode)
        
        let openSearch: () -> Void = {
            requestActivateSearch()
        }
        
        let arguments = NotificationExceptionArguments(account: context.account, activateSearch: {
            openSearch()
        }, openPeer: { [weak self] peer in
            if let strongSelf = self {
                _ = (strongSelf.context.account.postbox.transaction { transaction in
                    if transaction.getPeer(peer.id) == nil {
                        updatePeers(transaction: transaction, peers: [peer], update: { previousPeer, updatedPeer in
                            return updatedPeer
                        })
                    }
                } |> deliverOnMainQueue).start(completed: { [weak strongSelf] in
                        if let strongSelf = strongSelf, let infoController = peerInfoController(context: strongSelf.context, peer: peer) {
                            strongSelf.pushController(infoController)
                            strongSelf.requestDeactivateSearch()
                        }
                })
            }
            
        }, selectPeer: {
            var filter: ChatListNodePeersFilter = [.excludeRecent, .doNotSearchMessages, .removeSearchHeader]
            switch mode {
                case .groups:
                    filter.insert(.onlyGroups)
                case .users:
                    filter.insert(.onlyPrivateChats)
                    filter.insert(.excludeSavedMessages)
                    filter.insert(.excludeSecretChats)
                case .channels:
                    filter.insert(.onlyChannels)
            }
            let controller = PeerSelectionController(context: context, filter: filter, hasContactSelector: false, title: presentationData.strings.Notifications_AddExceptionTitle)
            controller.peerSelected = { [weak controller] peerId in
                controller?.dismiss()
                
                presentControllerImpl?(notificationPeerExceptionController(context: context, peerId: peerId, mode: mode, updatePeerSound: { peerId, sound in
                    _ = updatePeerSound(peerId, sound).start(next: { _ in
                        updateNotificationsDisposable.set(nil)
                       _ = combineLatest(updatePeerSound(peerId, sound), context.account.postbox.loadedPeerWithId(peerId) |> deliverOnMainQueue).start(next: { _, peer in
                            updateState { value in
                                return value.withUpdatedPeerSound(peer, sound)
                            }
                            updateNotificationsView()
                        })
                        
                    })
                }, updatePeerNotificationInterval: { peerId, muteInterval in
                    updateNotificationsDisposable.set(nil)
                   _ = combineLatest(updatePeerNotificationInterval(peerId, muteInterval), context.account.postbox.loadedPeerWithId(peerId) |> deliverOnMainQueue).start(next: { _, peer in
                        updateState { value in
                            return value.withUpdatedPeerMuteInterval(peer, muteInterval)
                        }
                        updateNotificationsView()
                    })
                }), ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
            }
            presentControllerImpl?(controller, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
        }, updateRevealedPeerId: { peerId in
            updateState { current in
                return current.withUpdatedRevealedPeerId(peerId)
            }
        }, deletePeer: { peer in
            _ = (context.account.postbox.transaction { transaction in
                if transaction.getPeer(peer.id) == nil {
                    updatePeers(transaction: transaction, peers: [peer], update: { _, updated in return updated})
                }
            } |> deliverOnMainQueue).start(completed: {
                updateNotificationsDisposable.set(nil)
                updateState { value in
                    return value.withUpdatedPeerMuteInterval(peer, nil).withUpdatedPeerSound(peer, .default)
                }
                _ = combineLatest(updatePeerSound(peer.id, .default), updatePeerNotificationInterval(peer.id, nil)).start(next: { _, _ in
                    updateNotificationsView()
                })
                
                
            })
           
        })
        
        self.arguments = arguments
        
        presentControllerImpl = { [weak self] c, a in
            self?.present(c, a)
        }
        
        let preferences = context.account.postbox.preferencesView(keys: [PreferencesKeys.globalNotifications])
        
        let previousEntriesHolder = Atomic<([NotificationExceptionEntry], PresentationTheme, PresentationStrings)?>(value: nil)

        self.listDisposable = (combineLatest(context.sharedContext.presentationData, statePromise.get(), preferences) |> deliverOnMainQueue).start(next: { [weak self] (presentationData, state, prefs) in
            let entries = notificationsExceptionEntries(presentationData: presentationData, state: state)
            let previousEntriesAndPresentationData = previousEntriesHolder.swap((entries, presentationData.theme, presentationData.strings))

            updateCanStartEditing(state.mode.peerIds.isEmpty ? nil : state.editing)
            
            let transition = preparedExceptionsListNodeTransition(theme: presentationData.theme, strings: presentationData.strings, from: previousEntriesAndPresentationData?.0 ?? [], to: entries, arguments: arguments, firstTime: previousEntriesAndPresentationData == nil, forceUpdate: previousEntriesAndPresentationData?.1 !== presentationData.theme || previousEntriesAndPresentationData?.2 !== presentationData.strings, animated: previousEntriesAndPresentationData != nil)
            
            self?.listNode.keepTopItemOverscrollBackground = entries.count <= 1 ? nil : ListViewKeepTopItemOverscrollBackground(color: presentationData.theme.chatList.backgroundColor, direction: true)
            
            
            self?.enqueueTransition(transition)
        })
    }
    
    deinit {
        self.listDisposable?.dispose()
        self.navigationActionDisposable.dispose()
        self.updateNotificationsDisposable.dispose()
    }
    
    func updatePresentationData(_ presentationData: PresentationData) {
        self.presentationData = presentationData
        self.presentationDataValue.set(.single((presentationData.theme, presentationData.strings)))
        self.backgroundColor = presentationData.theme.list.blocksBackgroundColor
        self.listNode.keepTopItemOverscrollBackground = ListViewKeepTopItemOverscrollBackground(color: presentationData.theme.chatList.backgroundColor, direction: true)
        self.searchDisplayController?.updatePresentationData(self.presentationData)
    }
    
    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, actualNavigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        let hadValidLayout = self.containerLayout != nil
        self.containerLayout = (layout, navigationBarHeight, actualNavigationBarHeight)
        
        var listInsets = layout.insets(options: [.input])
        listInsets.top += navigationBarHeight
        listInsets.left += layout.safeInsets.left
        listInsets.right += layout.safeInsets.right
        if let searchDisplayController = self.searchDisplayController {
            searchDisplayController.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: transition)
        }
        
        var headerInsets = layout.insets(options: [.input])
        headerInsets.top += actualNavigationBarHeight
        headerInsets.left += layout.safeInsets.left
        headerInsets.right += layout.safeInsets.right
        
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
        
        let updateSizeAndInsets = ListViewUpdateSizeAndInsets(size: layout.size, insets: listInsets, headerInsets: headerInsets, duration: duration, curve: listViewCurve)
        
        self.listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous, .LowLatency], scrollToItem: nil, updateSizeAndInsets: updateSizeAndInsets, stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
        
        if !hadValidLayout {
            self.dequeueTransitions()
        }
    }
    
    private func enqueueTransition(_ transition: NotificationExceptionNodeTransition) {
        self.queuedTransitions.append(transition)
        
        if self.containerLayout != nil {
            self.dequeueTransitions()
        }
    }
    
    private func dequeueTransitions() {
        if self.containerLayout != nil {
            while !self.queuedTransitions.isEmpty {
                let transition = self.queuedTransitions.removeFirst()
                
                var options = ListViewDeleteAndInsertOptions()
                if transition.firstTime {
                    options.insert(.Synchronous)
                    options.insert(.LowLatency)
                } else if transition.animated {
                    options.insert(.Synchronous)
                    options.insert(.AnimateInsertion)
                }
                self.listNode.transaction(deleteIndices: transition.deletions, insertIndicesAndItems: transition.insertions, updateIndicesAndItems: transition.updates, options: options, updateOpaqueState: nil, completion: { [weak self] _ in
                    if let strongSelf = self {
                        if !strongSelf.didSetReady {
                            strongSelf.didSetReady = true
                            strongSelf._ready.set(true)
                        }
                    }
                })
                
            }
        }
    }
    
    func toggleEditing() {
        self.statePromise.set(stateValue.modify({$0.withUpdatedEditing(!$0.editing).withUpdatedRevealedPeerId(nil)}))
    }
    
    func activateSearch(placeholderNode: SearchBarPlaceholderNode) {
        guard let (containerLayout, navigationBarHeight, _) = self.containerLayout, self.searchDisplayController == nil else {
            return
        }
        
        self.searchDisplayController = SearchDisplayController(presentationData: self.presentationData, contentNode: NotificationExceptionsSearchContainerNode(context: self.context, mode: self.stateValue.modify {$0}.mode, arguments: self.arguments!), cancel: { [weak self] in
            self?.requestDeactivateSearch()
        })
        
        self.searchDisplayController?.containerLayoutUpdated(containerLayout, navigationBarHeight: navigationBarHeight, transition: .immediate)
        self.searchDisplayController?.activate(insertSubnode: { [weak self, weak placeholderNode] subnode, isSearchBar in
            if let strongSelf = self, let strongPlaceholderNode = placeholderNode {
                if isSearchBar {
                    strongPlaceholderNode.supernode?.insertSubnode(subnode, aboveSubnode: strongPlaceholderNode)
                } else {
                    strongSelf.insertSubnode(subnode, belowSubnode: strongSelf.navigationBar)
                }
            }
        }, placeholder: placeholderNode)
    }
    
    func deactivateSearch(placeholderNode: SearchBarPlaceholderNode) {
        if let searchDisplayController = self.searchDisplayController {
            searchDisplayController.deactivate(placeholder: placeholderNode)
            self.searchDisplayController = nil
        }
    }
    
    func scrollToTop() {
        self.listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous, .LowLatency], scrollToItem: ListViewScrollToItem(index: 0, position: .top(0.0), animated: true, curve: .Default(duration: nil), directionHint: .Up), updateSizeAndInsets: nil, stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
    }
}


private struct NotificationExceptionsSearchContainerTransition {
    let deletions: [ListViewDeleteItem]
    let insertions: [ListViewInsertItem]
    let updates: [ListViewUpdateItem]
    let isSearching: Bool
}

private func preparedNotificationExceptionsSearchContainerTransition(theme: PresentationTheme, strings: PresentationStrings, from fromEntries: [NotificationExceptionEntry], to toEntries: [NotificationExceptionEntry], arguments: NotificationExceptionArguments, isSearching: Bool, forceUpdate: Bool) -> NotificationExceptionsSearchContainerTransition {
    let (deleteIndices, indicesAndItems, updateIndices) = mergeListsStableWithUpdates(leftList: fromEntries, rightList: toEntries, allUpdated: forceUpdate)
    
    let deletions = deleteIndices.map { ListViewDeleteItem(index: $0, directionHint: nil) }
    let insertions = indicesAndItems.map { ListViewInsertItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(arguments), directionHint: nil) }
    let updates = updateIndices.map { ListViewUpdateItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(arguments), directionHint: nil) }
    
    return NotificationExceptionsSearchContainerTransition(deletions: deletions, insertions: insertions, updates: updates, isSearching: isSearching)
}


private final class NotificationExceptionsSearchContainerNode: SearchDisplayControllerContentNode {
    private let dimNode: ASDisplayNode
    private let listNode: ListView
    
    private var enqueuedTransitions: [NotificationExceptionsSearchContainerTransition] = []
    private var hasValidLayout = false
    
    private let searchQuery = Promise<String?>()
    private let searchDisposable = MetaDisposable()
    
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?
    private let updateNotificationsDisposable = MetaDisposable()
    private let themeAndStringsPromise: Promise<(PresentationTheme, PresentationStrings)>
    
    init(context: AccountContext, mode: NotificationExceptionMode, arguments: NotificationExceptionArguments) {
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        
        self.themeAndStringsPromise = Promise((self.presentationData.theme, self.presentationData.strings))
        
        self.dimNode = ASDisplayNode()
        self.dimNode.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        
        self.listNode = ListView()
        
        super.init()
        
        self.listNode.backgroundColor = self.presentationData.theme.chatList.backgroundColor
        self.listNode.isHidden = true
        
        self.addSubnode(self.dimNode)
        self.addSubnode(self.listNode)
        
        let initialState = NotificationExceptionState(mode: mode, isSearchMode: true)
        let statePromise: ValuePromise<NotificationExceptionState> = ValuePromise(initialState, ignoreRepeated: true)
        let stateValue:Atomic<NotificationExceptionState> = Atomic(value: initialState)
        
        let updateState: ((NotificationExceptionState) -> NotificationExceptionState) -> Void = { f in
            statePromise.set(stateValue.modify { f($0) })
        }
        
        let updateNotificationsDisposable = self.updateNotificationsDisposable
        
        let updateNotificationsView:()->Void = {
            let key: PostboxViewKey = .peerNotificationSettings(peerIds: Set(mode.peerIds))
            
            updateNotificationsDisposable.set(context.account.postbox.combinedView(keys: [key]).start(next: { view in
                if let view = view.views[key] as? PeerNotificationSettingsView {
                    _ = context.account.postbox.transaction { transaction in
                        updateState { current in
                            var current = current
                            for (key, value) in view.notificationSettings {
                                if let value = value as? TelegramPeerNotificationSettings,let local = current.mode.settings[key] {
                                    if !value.isEqual(to: local.settings), let peer = transaction.getPeer(key), let settings = transaction.getPeerNotificationSettings(key) as? TelegramPeerNotificationSettings, !settings.isEqual(to: local.settings) {
                                        current = current.withUpdatedPeerSound(peer, settings.messageSound).withUpdatedPeerMuteInterval(peer, settings.muteState.timeInterval)
                                    }
                                }
                            }
                            return current
                        }
                    }.start()
                }
            }))
        }
        
        updateNotificationsView()
        
    
        let searchQuery = self.searchQuery.get()
        
        let stateAndPeers:Signal<(NotificationExceptionState, String?), NoError> = statePromise.get() |> mapToSignal { state -> Signal<(NotificationExceptionState, String?), NoError> in
            return searchQuery |> map { query -> (NotificationExceptionState, String?) in
                return (state, query)
            }
            
        }
        
        let preferences = context.account.postbox.preferencesView(keys: [PreferencesKeys.globalNotifications])
        
        
        let previousEntriesHolder = Atomic<([NotificationExceptionEntry], PresentationTheme, PresentationStrings)?>(value: nil)
        
        self.searchDisposable.set((combineLatest(context.sharedContext.presentationData, stateAndPeers, preferences) |> deliverOnMainQueue).start(next: { [weak self] (presentationData, state, prefs) in
            let entries = notificationsExceptionEntries(presentationData: presentationData, state: state.0, query: state.1)
            let previousEntriesAndPresentationData = previousEntriesHolder.swap((entries, presentationData.theme, presentationData.strings))
            
            let transition = preparedNotificationExceptionsSearchContainerTransition(theme: presentationData.theme, strings: presentationData.strings, from: previousEntriesAndPresentationData?.0 ?? [], to: entries, arguments: arguments, isSearching: state.1 != nil && !state.1!.isEmpty, forceUpdate: previousEntriesAndPresentationData?.1 !== presentationData.theme || previousEntriesAndPresentationData?.2 !== presentationData.strings)
            
            self?.enqueueTransition(transition)
        }))
        
        
        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            if let strongSelf = self {
                let previousTheme = strongSelf.presentationData.theme
                let previousStrings = strongSelf.presentationData.strings
                
                strongSelf.presentationData = presentationData
                
                if previousTheme !== presentationData.theme || previousStrings !== presentationData.strings {
                    strongSelf.updateThemeAndStrings(theme: presentationData.theme, strings: presentationData.strings)
                    strongSelf.themeAndStringsPromise.set(.single((presentationData.theme, presentationData.strings)))
                }
            }
        })
        
        self.listNode.beganInteractiveDragging = { [weak self] in
            self?.dismissInput?()
        }
    }
    
    deinit {
        self.searchDisposable.dispose()
        self.presentationDataDisposable?.dispose()
        self.updateNotificationsDisposable.dispose()
    }
    
    override func didLoad() {
        super.didLoad()
        
        self.dimNode.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.dimTapGesture(_:))))
    }
    
    private func updateThemeAndStrings(theme: PresentationTheme, strings: PresentationStrings) {
        self.listNode.backgroundColor = theme.chatList.backgroundColor
    }
    
    override func searchTextUpdated(text: String) {
        if text.isEmpty {
            self.searchQuery.set(.single(nil))
        } else {
            self.searchQuery.set(.single(text))
        }
    }
    
    private func enqueueTransition(_ transition: NotificationExceptionsSearchContainerTransition) {
        self.enqueuedTransitions.append(transition)
        
        if self.hasValidLayout {
            while !self.enqueuedTransitions.isEmpty {
                self.dequeueTransition()
            }
        }
    }
    
    private func dequeueTransition() {
        if let transition = self.enqueuedTransitions.first {
            self.enqueuedTransitions.remove(at: 0)
            
            var options = ListViewDeleteAndInsertOptions()
            options.insert(.PreferSynchronousDrawing)
            
            let isSearching = transition.isSearching
            self.listNode.transaction(deleteIndices: transition.deletions, insertIndicesAndItems: transition.insertions, updateIndicesAndItems: transition.updates, options: options, updateSizeAndInsets: nil, updateOpaqueState: nil, completion: { [weak self] _ in
                self?.listNode.isHidden = !isSearching
                self?.dimNode.isHidden = isSearching
            })
        }
    }
    
    override func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: transition)
        
        let topInset = navigationBarHeight
        transition.updateFrame(node: self.dimNode, frame: CGRect(origin: CGPoint(x: 0.0, y: topInset), size: CGSize(width: layout.size.width, height: layout.size.height - topInset)))
        
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
            listViewCurve = .Default(duration: nil)
        }
        
        self.listNode.frame = CGRect(origin: CGPoint(), size: layout.size)
        self.listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous], scrollToItem: nil, updateSizeAndInsets: ListViewUpdateSizeAndInsets(size: layout.size, insets: UIEdgeInsets(top: navigationBarHeight, left: 0.0, bottom: layout.insets(options: [.input]).bottom, right: 0.0), duration: duration, curve: listViewCurve), stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
        
        if !self.hasValidLayout {
            self.hasValidLayout = true
            while !self.enqueuedTransitions.isEmpty {
                self.dequeueTransition()
            }
        }
    }
    
    @objc func dimTapGesture(_ recognizer: UITapGestureRecognizer) {
        if case .ended = recognizer.state {
            self.cancel?()
        }
    }
}
