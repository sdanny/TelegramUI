import Foundation
import Display
import AsyncDisplayKit
import Postbox
import TelegramCore
import SwiftSignalKit


private enum NotificationPeerExceptionSection: Int32 {
    case switcher
    case soundModern
    case soundClassic
}

private enum NotificationPeerExceptionSwitcher : Equatable {
    case alwaysOn
    case alwaysOff
}

private enum NotificationPeerExceptionEntryId : Hashable {
    case switcher(NotificationPeerExceptionSwitcher)
    case sound(PeerMessageSound)
    case switcherHeader
    case soundModernHeader
    case soundClassicHeader
    case none
    case `default`
    
    var hashValue: Int {
        return 0
    }
}

private final class NotificationPeerExceptionArguments  {
    let account: Account
    
    let selectSound: (PeerMessageSound) -> Void
    let selectMode: (NotificationPeerExceptionSwitcher) -> Void
    let complete: () -> Void
    let cancel: () -> Void
    
    init(account: Account, selectSound: @escaping(PeerMessageSound) -> Void, selectMode: @escaping(NotificationPeerExceptionSwitcher) -> Void, complete: @escaping()->Void, cancel: @escaping() -> Void) {
        self.account = account
        self.selectSound = selectSound
        self.selectMode = selectMode
        self.complete = complete
        self.cancel = cancel
    }
}


private enum NotificationPeerExceptionEntry: ItemListNodeEntry {
    
    typealias ItemGenerationArguments = NotificationPeerExceptionArguments
    
    case switcher(index:Int32, theme: PresentationTheme, strings: PresentationStrings, mode: NotificationPeerExceptionSwitcher, selected: Bool)
    case switcherHeader(index:Int32, theme: PresentationTheme, title: String)
    case soundModernHeader(index:Int32, theme: PresentationTheme, title: String)
    case soundClassicHeader(index:Int32, theme: PresentationTheme, title: String)
    case none(index:Int32, section: NotificationPeerExceptionSection, theme: PresentationTheme, text: String, selected: Bool)
    case `default`(index:Int32, section: NotificationPeerExceptionSection, theme: PresentationTheme, text: String, selected: Bool)
    case sound(index:Int32, section: NotificationPeerExceptionSection, theme: PresentationTheme, text: String, sound: PeerMessageSound, selected: Bool)
    
    
    var index: Int32 {
        switch self {
        case let .switcherHeader(index, _, _):
            return index
        case let .switcher(index, _, _, _, _):
            return index
        case let .soundModernHeader(index, _, _):
            return index
        case let .soundClassicHeader(index, _, _):
            return index
        case let .none(index, _, _, _, _):
            return index
        case let .default(index, _, _, _, _):
            return index
        case let .sound(index, _, _, _, _, _):
            return index
        }
    }
    
    var section: ItemListSectionId {
        switch self {
        case .switcher, .switcherHeader:
            return NotificationPeerExceptionSection.switcher.rawValue
        case .soundModernHeader:
            return NotificationPeerExceptionSection.soundModern.rawValue
        case .soundClassicHeader:
            return NotificationPeerExceptionSection.soundClassic.rawValue
        case let .none(_, section, _, _, _):
            return section.rawValue
        case let .default(_, section, _, _, _):
            return section.rawValue
        case let .sound(_, section, _, _, _, _):
            return section.rawValue
        }
    }
    
    var stableId: NotificationPeerExceptionEntryId {
        switch self {
        case let .switcher(_, _, _, mode, _):
            return .switcher(mode)
        case .switcherHeader:
            return .switcherHeader
        case .soundModernHeader:
            return .soundModernHeader
        case .soundClassicHeader:
            return .soundClassicHeader
        case .none:
            return .none
        case .default:
            return .default
        case let .sound(_, _, _, _, sound, _):
            return .sound(sound)
        }
    }

    static func <(lhs: NotificationPeerExceptionEntry, rhs: NotificationPeerExceptionEntry) -> Bool {
        return lhs.index < rhs.index
    }
    
    func item(_ arguments: NotificationPeerExceptionArguments) -> ListViewItem {
        switch self {
        case let .switcher(_, theme, strings, mode, selected):
            let title: String
            switch mode {
            case .alwaysOn:
                title = strings.Notification_Exceptions_AlwaysOn
            case .alwaysOff:
                title = strings.Notification_Exceptions_AlwaysOff
            }
            return ItemListCheckboxItem(theme: theme, title: title, style: .left, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                 arguments.selectMode(mode)
            })
        case let .switcherHeader(_, theme, text):
            return ItemListSectionHeaderItem(theme: theme, text: text, sectionId: self.section)
        case let .soundModernHeader(_, theme, text):
            return ItemListSectionHeaderItem(theme: theme, text: text, sectionId: self.section)
        case let .soundClassicHeader(_, theme, text):
            return ItemListSectionHeaderItem(theme: theme, text: text, sectionId: self.section)
        case let .none(_, _, theme, text, selected):
            return ItemListCheckboxItem(theme: theme, title: text, style: .left, checked: selected, zeroSeparatorInsets: true, sectionId: self.section, action: {
                arguments.selectSound(.none)
            })
        case let .default(_, _, theme, text, selected):
            return ItemListCheckboxItem(theme: theme, title: text, style: .left, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.selectSound(.default)
            })
        case let .sound(_, _, theme, text, sound, selected):
            return ItemListCheckboxItem(theme: theme, title: text, style: .left, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.selectSound(sound)
            })
        }
    }
}


private func notificationPeerExceptionEntries(presentationData: PresentationData, state: NotificationExceptionPeerState) -> [NotificationPeerExceptionEntry] {
    var entries:[NotificationPeerExceptionEntry] = []
    
    var index: Int32 = 0
    
    entries.append(.switcherHeader(index: index, theme: presentationData.theme, title: presentationData.strings.Notification_Exceptions_NewException_NotificationHeader))
    index += 1

    
    entries.append(.switcher(index: index, theme: presentationData.theme, strings: presentationData.strings, mode: .alwaysOn, selected: state.mode == .alwaysOn))
    index += 1
    entries.append(.switcher(index: index, theme: presentationData.theme, strings: presentationData.strings, mode: .alwaysOff, selected:  state.mode == .alwaysOff))
    index += 1

    
    entries.append(.soundModernHeader(index: index, theme: presentationData.theme, title: presentationData.strings.Notifications_AlertTones))
    index += 1
    
    if state.selectedSound == .default {
        var bp:Int = 0
        bp += 1
    }
    
    entries.append(.default(index: index, section: .soundModern, theme: presentationData.theme, text: localizedPeerNotificationSoundString(strings: presentationData.strings, sound: .default, default: state.defaultSound), selected: state.selectedSound == .default))
    index += 1

    entries.append(.none(index: index, section: .soundModern, theme: presentationData.theme, text: localizedPeerNotificationSoundString(strings: presentationData.strings, sound: .none), selected: state.selectedSound == .none))
    index += 1

    for i in 0 ..< 12 {
        let sound: PeerMessageSound = .bundledModern(id: Int32(i))
        entries.append(.sound(index: index, section: .soundModern, theme: presentationData.theme, text: localizedPeerNotificationSoundString(strings: presentationData.strings, sound: sound), sound: sound, selected: sound == state.selectedSound))
        index += 1
    }
    
    entries.append(.soundClassicHeader(index: index, theme: presentationData.theme, title: presentationData.strings.Notifications_ClassicTones))
    for i in 0 ..< 8 {
        let sound: PeerMessageSound = .bundledClassic(id: Int32(i))
        entries.append(.sound(index: index, section: .soundClassic, theme: presentationData.theme, text: localizedPeerNotificationSoundString(strings: presentationData.strings, sound: sound), sound: sound, selected: sound == state.selectedSound))
        index += 1
    }
    
    return entries
}

private struct NotificationExceptionPeerState : Equatable {
    let selectedSound: PeerMessageSound
    let mode: NotificationPeerExceptionSwitcher
    let defaultSound: PeerMessageSound
    init(notifications: TelegramPeerNotificationSettings? = nil) {
        
        if let notifications = notifications {
            self.selectedSound = notifications.messageSound
            switch notifications.muteState {
            case .muted:
                self.mode = .alwaysOff
            case .unmuted:
                self.mode = .alwaysOn
            case .default:
                self.mode = .alwaysOn
            }
        } else {
            self.selectedSound = .default
            self.mode = .alwaysOn
        }
        
      
        self.defaultSound = .default
    }
    
    init(selectedSound: PeerMessageSound, mode: NotificationPeerExceptionSwitcher, defaultSound: PeerMessageSound) {
        self.selectedSound = selectedSound
        self.mode = mode
        self.defaultSound = defaultSound
    }
    
    func withUpdatedDefaultSound(_ defaultSound: PeerMessageSound) -> NotificationExceptionPeerState {
        return NotificationExceptionPeerState(selectedSound: self.selectedSound, mode: self.mode, defaultSound: defaultSound)
    }
    func withUpdatedSound(_ selectedSound: PeerMessageSound) -> NotificationExceptionPeerState {
        return NotificationExceptionPeerState(selectedSound: selectedSound, mode: self.mode, defaultSound: self.defaultSound)
    }
    func withUpdatedMode(_ mode: NotificationPeerExceptionSwitcher) -> NotificationExceptionPeerState {
        return NotificationExceptionPeerState(selectedSound: self.selectedSound, mode: mode, defaultSound: self.defaultSound)
    }
}


func notificationPeerExceptionController(context: AccountContext, peerId: PeerId, mode: NotificationExceptionMode, updatePeerSound: @escaping(PeerId, PeerMessageSound) -> Void, updatePeerNotificationInterval: @escaping(PeerId, Int32?) -> Void) -> ViewController {
    let initialState = NotificationExceptionPeerState()
    let statePromise = Promise(initialState)
    let stateValue = Atomic(value: initialState)
    let updateState: ((NotificationExceptionPeerState) -> NotificationExceptionPeerState) -> Void = { f in
        statePromise.set(.single(stateValue.modify { f($0) }))
    }
    
    var completeImpl: (() -> Void)?
    var cancelImpl: (() -> Void)?
    let playSoundDisposable = MetaDisposable()


    let arguments = NotificationPeerExceptionArguments(account: context.account, selectSound: { sound in
      
        updateState { state in
            playSoundDisposable.set(playSound(context: context, sound: sound, defaultSound: state.defaultSound).start())
            return state.withUpdatedSound(sound)
        }

    }, selectMode: { mode in
        updateState { state in
            return state.withUpdatedMode(mode)
        }
    }, complete: {
        completeImpl?()
    }, cancel: {
        cancelImpl?()
    })
    
    
    
    
    statePromise.set(context.account.postbox.transaction { transaction -> NotificationExceptionPeerState in
        var state = NotificationExceptionPeerState(notifications: transaction.getPeerNotificationSettings(peerId) as? TelegramPeerNotificationSettings)
        let globalSettings: GlobalNotificationSettings = (transaction.getPreferencesEntry(key: PreferencesKeys.globalNotifications) as? GlobalNotificationSettings) ?? GlobalNotificationSettings.defaultSettings
        switch mode {
        case .channels:
            state = state.withUpdatedDefaultSound(globalSettings.effective.channels.sound)
        case .groups:
            state = state.withUpdatedDefaultSound(globalSettings.effective.groupChats.sound)
        case .users:
            state = state.withUpdatedDefaultSound(globalSettings.effective.privateChats.sound)
        }
        _ = stateValue.swap(state)
        return state
    })
    
    
    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get() |> distinctUntilChanged)
        |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState<NotificationPeerExceptionEntry>, NotificationPeerExceptionEntry.ItemGenerationArguments)) in
            
            let leftNavigationButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Cancel), style: .regular, enabled: true, action: {
                arguments.cancel()
            })
            
            let rightNavigationButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Done), style: .bold, enabled: true, action: {
                arguments.complete()
            })
            
            let controllerState = ItemListControllerState(theme: presentationData.theme, title: .text(presentationData.strings.Notification_Exceptions_NewException), leftNavigationButton: leftNavigationButton, rightNavigationButton: rightNavigationButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
            let listState = ItemListNodeState(entries: notificationPeerExceptionEntries(presentationData: presentationData, state: state), style: .blocks)
            
            return (controllerState, (listState, arguments))
    }
    
    let controller = ItemListController(context: context, state: signal |> afterDisposed {
        playSoundDisposable.dispose()
    })

    controller.enableInteractiveDismiss = true
    
    completeImpl = { [weak controller] in
        controller?.dismiss()
        updateState { state in
            updatePeerSound(peerId, state.selectedSound)
            updatePeerNotificationInterval(peerId, state.mode == .alwaysOn ? 0 : Int32.max)
            return state
        }
    }
    
    cancelImpl = { [weak controller] in
        controller?.dismiss()
    }

    return controller
}
