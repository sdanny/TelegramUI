import Foundation
import Display
import SwiftSignalKit
import Postbox
import TelegramCore

private final class SelectivePrivacyPeersControllerArguments {
    let account: Account
    
    let setPeerIdWithRevealedOptions: (PeerId?, PeerId?) -> Void
    let removePeer: (PeerId) -> Void
    let addPeer: () -> Void
    
    init(account: Account, setPeerIdWithRevealedOptions: @escaping (PeerId?, PeerId?) -> Void, removePeer: @escaping (PeerId) -> Void, addPeer: @escaping () -> Void) {
        self.account = account
        self.setPeerIdWithRevealedOptions = setPeerIdWithRevealedOptions
        self.removePeer = removePeer
        self.addPeer = addPeer
    }
}

private enum SelectivePrivacyPeersSection: Int32 {
    case peers
    case add
}

private enum SelectivePrivacyPeersEntryStableId: Hashable {
    case peer(PeerId)
    case add
    
    var hashValue: Int {
        switch self {
            case let .peer(peerId):
                return peerId.hashValue
            case .add:
                return 1
        }
    }
    
    static func ==(lhs: SelectivePrivacyPeersEntryStableId, rhs: SelectivePrivacyPeersEntryStableId) -> Bool {
        switch lhs {
            case let .peer(peerId):
                if case .peer(peerId) = rhs {
                    return true
                } else {
                    return false
                }
            case .add:
                if case .add = rhs {
                    return true
                } else {
                    return false
                }
        }
    }
}

private enum SelectivePrivacyPeersEntry: ItemListNodeEntry {
    case peerItem(Int32, PresentationTheme, PresentationStrings, PresentationDateTimeFormat, PresentationPersonNameOrder, Peer, ItemListPeerItemEditing, Bool)
    case addItem(PresentationTheme, String, Bool)
    
    var section: ItemListSectionId {
        switch self {
            case .peerItem:
                return SelectivePrivacyPeersSection.peers.rawValue
            case .addItem:
                return SelectivePrivacyPeersSection.add.rawValue
        }
    }
    
    var stableId: SelectivePrivacyPeersEntryStableId {
        switch self {
            case let .peerItem(_, _, _, _, _, peer, _, _):
                return .peer(peer.id)
            case .addItem:
                return .add
        }
    }
    
    static func ==(lhs: SelectivePrivacyPeersEntry, rhs: SelectivePrivacyPeersEntry) -> Bool {
        switch lhs {
        case let .peerItem(lhsIndex, lhsTheme, lhsStrings, lhsDateTimeFormat, lhsNameOrder, lhsPeer, lhsEditing, lhsEnabled):
                if case let .peerItem(rhsIndex, rhsTheme, rhsStrings, rhsDateTimeFormat, rhsNameOrder, rhsPeer, rhsEditing, rhsEnabled) = rhs {
                    if lhsIndex != rhsIndex {
                        return false
                    }
                    if !lhsPeer.isEqual(rhsPeer) {
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
            case let .addItem(lhsTheme, lhsText, lhsEditing):
                if case let .addItem(rhsTheme, rhsText, rhsEditing) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsEditing == rhsEditing {
                    return true
                } else {
                    return false
                }
        }
    }
    
    static func <(lhs: SelectivePrivacyPeersEntry, rhs: SelectivePrivacyPeersEntry) -> Bool {
        switch lhs {
            case let .peerItem(index, _, _, _, _, _, _, _):
                switch rhs {
                    case let .peerItem(rhsIndex, _, _, _, _, _, _, _):
                        return index < rhsIndex
                    case .addItem:
                        return true
                }
            case .addItem:
                return false
        }
    }
    
    func item(_ arguments: SelectivePrivacyPeersControllerArguments) -> ListViewItem {
        switch self {
            case let .peerItem(_, theme, strings, dateTimeFormat, nameDisplayOrder, peer, editing, enabled):
                return ItemListPeerItem(theme: theme, strings: strings, dateTimeFormat: dateTimeFormat, nameDisplayOrder: nameDisplayOrder, account: arguments.account, peer: peer, presence: nil, text: .none, label: .none, editing: editing, switchValue: nil, enabled: enabled, sectionId: self.section, action: nil, setPeerIdWithRevealedOptions: { previousId, id in
                    arguments.setPeerIdWithRevealedOptions(previousId, id)
                }, removePeer: { peerId in
                    arguments.removePeer(peerId)
                })
            case let .addItem(theme, text, editing):
                return ItemListPeerActionItem(theme: theme, icon: PresentationResourcesItemList.addPersonIcon(theme), title: text, sectionId: self.section, editing: editing, action: {
                    arguments.addPeer()
                })
        }
    }
}

private struct SelectivePrivacyPeersControllerState: Equatable {
    let editing: Bool
    let peerIdWithRevealedOptions: PeerId?
    
    init() {
        self.editing = false
        self.peerIdWithRevealedOptions = nil
    }
    
    init(editing: Bool, peerIdWithRevealedOptions: PeerId?) {
        self.editing = editing
        self.peerIdWithRevealedOptions = peerIdWithRevealedOptions
    }
    
    static func ==(lhs: SelectivePrivacyPeersControllerState, rhs: SelectivePrivacyPeersControllerState) -> Bool {
        if lhs.editing != rhs.editing {
            return false
        }
        if lhs.peerIdWithRevealedOptions != rhs.peerIdWithRevealedOptions {
            return false
        }
        return true
    }
    
    func withUpdatedEditing(_ editing: Bool) -> SelectivePrivacyPeersControllerState {
        return SelectivePrivacyPeersControllerState(editing: editing, peerIdWithRevealedOptions: self.peerIdWithRevealedOptions)
    }
    
    func withUpdatedPeerIdWithRevealedOptions(_ peerIdWithRevealedOptions: PeerId?) -> SelectivePrivacyPeersControllerState {
        return SelectivePrivacyPeersControllerState(editing: self.editing, peerIdWithRevealedOptions: peerIdWithRevealedOptions)
    }
}

private func selectivePrivacyPeersControllerEntries(presentationData: PresentationData, state: SelectivePrivacyPeersControllerState, peers: [Peer]) -> [SelectivePrivacyPeersEntry] {
    var entries: [SelectivePrivacyPeersEntry] = []
    
    var index: Int32 = 0
    for peer in peers {
        entries.append(.peerItem(index, presentationData.theme, presentationData.strings, presentationData.dateTimeFormat, presentationData.nameDisplayOrder, peer, ItemListPeerItemEditing(editable: true, editing: state.editing, revealed: peer.id == state.peerIdWithRevealedOptions), true))
        index += 1
    }
    
    entries.append(.addItem(presentationData.theme, presentationData.strings.BlockedUsers_AddNew, state.editing))
    
    return entries
}

public func selectivePrivacyPeersController(context: AccountContext, title: String, initialPeerIds: [PeerId], updated: @escaping ([PeerId]) -> Void) -> ViewController {
    let statePromise = ValuePromise(SelectivePrivacyPeersControllerState(), ignoreRepeated: true)
    let stateValue = Atomic(value: SelectivePrivacyPeersControllerState())
    let updateState: ((SelectivePrivacyPeersControllerState) -> SelectivePrivacyPeersControllerState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }
    
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    
    let actionsDisposable = DisposableSet()
    
    let addPeerDisposable = MetaDisposable()
    actionsDisposable.add(addPeerDisposable)
    
    let removePeerDisposable = MetaDisposable()
    actionsDisposable.add(removePeerDisposable)
    
    let peersPromise = Promise<[Peer]>()
    peersPromise.set(context.account.postbox.transaction { transaction -> [Peer] in
        var result: [Peer] = []
        for peerId in initialPeerIds {
            if let peer = transaction.getPeer(peerId) {
                result.append(peer)
            }
        }
        return result
    })
    
    let arguments = SelectivePrivacyPeersControllerArguments(account: context.account, setPeerIdWithRevealedOptions: { peerId, fromPeerId in
        updateState { state in
            if (peerId == nil && fromPeerId == state.peerIdWithRevealedOptions) || (peerId != nil && fromPeerId == nil) {
                return state.withUpdatedPeerIdWithRevealedOptions(peerId)
            } else {
                return state
            }
        }
    }, removePeer: { memberId in
        let applyPeers: Signal<Void, NoError> = peersPromise.get()
            |> take(1)
            |> deliverOnMainQueue
            |> mapToSignal { peers -> Signal<Void, NoError> in
                var updatedPeers = peers
                for i in 0 ..< updatedPeers.count {
                    if updatedPeers[i].id == memberId {
                        updatedPeers.remove(at: i)
                        break
                    }
                }
                peersPromise.set(.single(updatedPeers))
                updated(updatedPeers.map { $0.id })
                
                return .complete()
        }
        
        removePeerDisposable.set(applyPeers.start())
    }, addPeer: {
        let controller = ContactMultiselectionController(context: context, mode: .peerSelection(searchChatList: true), options: [])
        addPeerDisposable.set((controller.result |> take(1) |> deliverOnMainQueue).start(next: { [weak controller] peerIds in
            let applyPeers: Signal<Void, NoError> = peersPromise.get()
            |> take(1)
            |> mapToSignal { peers -> Signal<[Peer], NoError> in
                return context.account.postbox.transaction { transaction -> [Peer] in
                    var updatedPeers = peers
                    var existingIds = Set(updatedPeers.map { $0.id })
                    for peerId in peerIds {
                        guard case let .peer(peerId) = peerId else {
                            continue
                        }
                        if let peer = transaction.getPeer(peerId), !existingIds.contains(peerId) {
                            existingIds.insert(peerId)
                            updatedPeers.append(peer)
                        }
                    }
                    return updatedPeers
                }
            }
            |> deliverOnMainQueue
            |> mapToSignal { updatedPeers -> Signal<Void, NoError> in
                peersPromise.set(.single(updatedPeers))
                updated(updatedPeers.map { $0.id })
                return .complete()
            }
            
            removePeerDisposable.set(applyPeers.start())
            controller?.dismiss()
        }))
        presentControllerImpl?(controller, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
    })
    
    var previousPeers: [Peer]?
    
    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get(), peersPromise.get())
        |> deliverOnMainQueue
        |> map { presentationData, state, peers -> (ItemListControllerState, (ItemListNodeState<SelectivePrivacyPeersEntry>, SelectivePrivacyPeersEntry.ItemGenerationArguments)) in
            var rightNavigationButton: ItemListNavigationButton?
            if !peers.isEmpty {
                if state.editing {
                    rightNavigationButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Done), style: .bold, enabled: true, action: {
                        updateState { state in
                            return state.withUpdatedEditing(false)
                        }
                    })
                } else {
                    rightNavigationButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Edit), style: .regular, enabled: true, action: {
                        updateState { state in
                            return state.withUpdatedEditing(true)
                        }
                    })
                }
            }
            
            let previous = previousPeers
            previousPeers = peers
            
            let controllerState = ItemListControllerState(theme: presentationData.theme, title: .text(title), leftNavigationButton: nil, rightNavigationButton: rightNavigationButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: true)
            let listState = ItemListNodeState(entries: selectivePrivacyPeersControllerEntries(presentationData: presentationData, state: state, peers: peers), style: .blocks, emptyStateItem: nil, animateChanges: previous != nil && previous!.count >= peers.count)
            
            return (controllerState, (listState, arguments))
        } |> afterDisposed {
            actionsDisposable.dispose()
    }
    
    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c, p in
        if let controller = controller {
            controller.present(c, in: .window(.root), with: p)
        }
    }
    return controller
}
