import Foundation
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import MtProtoKitDynamic

private final class DebugControllerArguments {
    let sharedContext: SharedAccountContext
    let context: AccountContext?
    let presentController: (ViewController, ViewControllerPresentationArguments?) -> Void
    let pushController: (ViewController) -> Void
    
    init(sharedContext: SharedAccountContext, context: AccountContext?, presentController: @escaping (ViewController, ViewControllerPresentationArguments?) -> Void, pushController: @escaping (ViewController) -> Void) {
        self.sharedContext = sharedContext
        self.context = context
        self.presentController = presentController
        self.pushController = pushController
    }
}

private enum DebugControllerSection: Int32 {
    case logs
    case logging
    case experiments
    case info
}

private enum DebugControllerEntry: ItemListNodeEntry {
    case sendLogs(PresentationTheme)
    case sendOneLog(PresentationTheme)
    case sendNotificationLogs(PresentationTheme)
    case accounts(PresentationTheme)
    case logToFile(PresentationTheme, Bool)
    case logToConsole(PresentationTheme, Bool)
    case redactSensitiveData(PresentationTheme, Bool)
    case enableRaiseToSpeak(PresentationTheme, Bool)
    case keepChatNavigationStack(PresentationTheme, Bool)
    case clearTips(PresentationTheme)
    case reimport(PresentationTheme)
    case resetData(PresentationTheme)
    case animatedStickers(PresentationTheme)
    case versionInfo(PresentationTheme)
    
    var section: ItemListSectionId {
        switch self {
            case .sendLogs, .sendOneLog, .sendNotificationLogs:
                return DebugControllerSection.logs.rawValue
            case .accounts:
                return DebugControllerSection.logs.rawValue
            case .logToFile, .logToConsole, .redactSensitiveData:
                return DebugControllerSection.logging.rawValue
            case .enableRaiseToSpeak, .keepChatNavigationStack:
                return DebugControllerSection.experiments.rawValue
            case .clearTips, .reimport, .resetData, .animatedStickers:
                return DebugControllerSection.experiments.rawValue
            case .versionInfo:
                return DebugControllerSection.info.rawValue
        }
    }
    
    var stableId: Int32 {
        switch self {
            case .sendLogs:
                return 0
            case .sendOneLog:
                return 1
            case .sendNotificationLogs:
                return 2
            case .accounts:
                return 3
            case .logToFile:
                return 4
            case .logToConsole:
                return 5
            case .redactSensitiveData:
                return 6
            case .enableRaiseToSpeak:
                return 7
            case .keepChatNavigationStack:
                return 8
            case .clearTips:
                return 10
            case .reimport:
                return 11
            case .resetData:
                return 12
            case .animatedStickers:
                return 14
            case .versionInfo:
                return 15
        }
    }
    
    static func <(lhs: DebugControllerEntry, rhs: DebugControllerEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }
    
    func item(_ arguments: DebugControllerArguments) -> ListViewItem {
        switch self {
            case let .sendLogs(theme):
                return ItemListDisclosureItem(theme: theme, title: "Send Logs", label: "", sectionId: self.section, style: .blocks, action: {
                    let _ = (Logger.shared.collectLogs()
                    |> deliverOnMainQueue).start(next: { logs in
                        guard let context = arguments.context else {
                            return
                        }
                        let controller = PeerSelectionController(context: context)
                        controller.peerSelected = { [weak controller] peerId in
                            if let strongController = controller {
                                strongController.dismiss()
                                
                                let messages = logs.map { (name, path) -> EnqueueMessage in
                                    let id = arc4random64()
                                    let file = TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: id), partialReference: nil, resource: LocalFileReferenceMediaResource(localFilePath: path, randomId: id), previewRepresentations: [], immediateThumbnailData: nil, mimeType: "application/text", size: nil, attributes: [.FileName(fileName: name)])
                                    return .message(text: "", attributes: [], mediaReference: .standalone(media: file), replyToMessageId: nil, localGroupingKey: nil)
                                }
                                let _ = enqueueMessages(account: context.account, peerId: peerId, messages: messages).start()
                            }
                        }
                        arguments.presentController(controller, ViewControllerPresentationArguments(presentationAnimation: ViewControllerPresentationAnimation.modalSheet))
                    })
                })
            case let .sendOneLog(theme):
                return ItemListDisclosureItem(theme: theme, title: "Send Latest Log", label: "", sectionId: self.section, style: .blocks, action: {
                    let _ = (Logger.shared.collectLogs()
                    |> deliverOnMainQueue).start(next: { logs in
                        guard let context = arguments.context else {
                            return
                        }
                        let controller = PeerSelectionController(context: context)
                        controller.peerSelected = { [weak controller] peerId in
                            if let strongController = controller {
                                strongController.dismiss()
                                
                                let updatedLogs = logs.last.flatMap({ [$0] }) ?? []
                                
                                let messages = updatedLogs.map { (name, path) -> EnqueueMessage in
                                    let id = arc4random64()
                                    let file = TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: id), partialReference: nil, resource: LocalFileReferenceMediaResource(localFilePath: path, randomId: id), previewRepresentations: [], immediateThumbnailData: nil, mimeType: "application/text", size: nil, attributes: [.FileName(fileName: name)])
                                    return .message(text: "", attributes: [], mediaReference: .standalone(media: file), replyToMessageId: nil, localGroupingKey: nil)
                                }
                                let _ = enqueueMessages(account: context.account, peerId: peerId, messages: messages).start()
                            }
                        }
                        arguments.presentController(controller, ViewControllerPresentationArguments(presentationAnimation: ViewControllerPresentationAnimation.modalSheet))
                    })
                })
            case let .sendNotificationLogs(theme):
                return ItemListDisclosureItem(theme: theme, title: "Send Notification Logs", label: "", sectionId: self.section, style: .blocks, action: {
                    let _ = (Logger(basePath: arguments.sharedContext.basePath + "/notificationServiceLogs").collectLogs()
                    |> deliverOnMainQueue).start(next: { logs in
                        guard let context = arguments.context else {
                            return
                        }
                        let controller = PeerSelectionController(context: context)
                        controller.peerSelected = { [weak controller] peerId in
                            if let strongController = controller {
                                strongController.dismiss()
                                
                                let messages = logs.map { (name, path) -> EnqueueMessage in
                                    let id = arc4random64()
                                    let file = TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: id), partialReference: nil, resource: LocalFileReferenceMediaResource(localFilePath: path, randomId: id), previewRepresentations: [], immediateThumbnailData: nil, mimeType: "application/text", size: nil, attributes: [.FileName(fileName: name)])
                                    return .message(text: "", attributes: [], mediaReference: .standalone(media: file), replyToMessageId: nil, localGroupingKey: nil)
                                }
                                let _ = enqueueMessages(account: context.account, peerId: peerId, messages: messages).start()
                            }
                        }
                        arguments.presentController(controller, ViewControllerPresentationArguments(presentationAnimation: ViewControllerPresentationAnimation.modalSheet))
                    })
                })
            case let .accounts(theme):
                return ItemListDisclosureItem(theme: theme, title: "Accounts", label: "", sectionId: self.section, style: .blocks, action: {
                    guard let context = arguments.context else {
                        return
                    }
                    arguments.pushController(debugAccountsController(context: context, accountManager: arguments.sharedContext.accountManager))
                })
            case let .logToFile(theme, value):
                return ItemListSwitchItem(theme: theme, title: "Log to File", value: value, sectionId: self.section, style: .blocks, updated: { value in
                    let _ = updateLoggingSettings(accountManager: arguments.sharedContext.accountManager, {
                        $0.withUpdatedLogToFile(value)
                    }).start()
                })
            case let .logToConsole(theme, value):
                return ItemListSwitchItem(theme: theme, title: "Log to Console", value: value, sectionId: self.section, style: .blocks, updated: { value in
                    let _ = updateLoggingSettings(accountManager: arguments.sharedContext.accountManager, {
                        $0.withUpdatedLogToConsole(value)
                    }).start()
                })
            case let .redactSensitiveData(theme, value):
                return ItemListSwitchItem(theme: theme, title: "Remove Sensitive Data", value: value, sectionId: self.section, style: .blocks, updated: { value in
                    let _ = updateLoggingSettings(accountManager: arguments.sharedContext.accountManager, {
                        $0.withUpdatedRedactSensitiveData(value)
                    }).start()
                })
            case let .enableRaiseToSpeak(theme, value):
                return ItemListSwitchItem(theme: theme, title: "Enable Raise to Speak", value: value, sectionId: self.section, style: .blocks, updated: { value in
                    let _ = updateMediaInputSettingsInteractively(accountManager: arguments.sharedContext.accountManager, {
                        $0.withUpdatedEnableRaiseToSpeak(value)
                    }).start()
                })
            case let .keepChatNavigationStack(theme, value):
                return ItemListSwitchItem(theme: theme, title: "Keep Chat Stack", value: value, sectionId: self.section, style: .blocks, updated: { value in
                    let _ = updateExperimentalUISettingsInteractively(accountManager: arguments.sharedContext.accountManager, { settings in
                        var settings = settings
                        settings.keepChatNavigationStack = value
                        return settings
                    }).start()
                })
            case let .clearTips(theme):
                return ItemListActionItem(theme: theme, title: "Clear Tips", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                    let _ = (arguments.sharedContext.accountManager.transaction { transaction -> Void in
                        transaction.clearNotices()
                    }).start()
                })
            case let .reimport(theme):
                return ItemListActionItem(theme: theme, title: "Reimport Application Data", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                    let appGroupName = "group.\(Bundle.main.bundleIdentifier!)"
                    let maybeAppGroupUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupName)
                    
                    guard let appGroupUrl = maybeAppGroupUrl else {
                        return
                    }
                    
                    let statusPath = appGroupUrl.path + "/Documents/importcompleted"
                    if FileManager.default.fileExists(atPath: statusPath) {
                        let _ = try? FileManager.default.removeItem(at: URL(fileURLWithPath: statusPath))
                        exit(0)
                    }
                })
            case let .resetData(theme):
                return ItemListActionItem(theme: theme, title: "Reset Data", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                    let presentationData = arguments.sharedContext.currentPresentationData.with { $0 }
                    let actionSheet = ActionSheetController(presentationTheme: presentationData.theme)
                    actionSheet.setItemGroups([ActionSheetItemGroup(items: [
                        ActionSheetTextItem(title: "All data will be lost."),
                        ActionSheetButtonItem(title: "Reset Data", color: .destructive, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                            let databasePath = arguments.sharedContext.accountManager.basePath + "/db"
                            let _ = try? FileManager.default.removeItem(atPath: databasePath)
                            preconditionFailure()
                        }),
                    ]), ActionSheetItemGroup(items: [
                        ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                        })
                    ])])
                    arguments.presentController(actionSheet, nil)
                })
            case let .animatedStickers(theme):
                return ItemListSwitchItem(theme: theme, title: "AJSON", value: GlobalExperimentalSettings.animatedStickers, sectionId: self.section, style: .blocks, updated: { value in
                    GlobalExperimentalSettings.animatedStickers = value
                })
            case let .versionInfo(theme):
                let bundle = Bundle.main
                let bundleId = bundle.bundleIdentifier ?? ""
                let bundleVersion = bundle.infoDictionary?["CFBundleShortVersionString"] ?? ""
                let bundleBuild = bundle.infoDictionary?[kCFBundleVersionKey as String] ?? ""
                return ItemListTextItem(theme: theme, text: .plain("\(bundleId)\n\(bundleVersion) (\(bundleBuild))"), sectionId: self.section)
        }
    }
}

private func debugControllerEntries(presentationData: PresentationData, loggingSettings: LoggingSettings, mediaInputSettings: MediaInputSettings, experimentalSettings: ExperimentalUISettings, hasLegacyAppData: Bool) -> [DebugControllerEntry] {
    var entries: [DebugControllerEntry] = []
    
    entries.append(.sendLogs(presentationData.theme))
    entries.append(.sendOneLog(presentationData.theme))
    entries.append(.sendNotificationLogs(presentationData.theme))
    entries.append(.accounts(presentationData.theme))
    
    entries.append(.logToFile(presentationData.theme, loggingSettings.logToFile))
    entries.append(.logToConsole(presentationData.theme, loggingSettings.logToConsole))
    entries.append(.redactSensitiveData(presentationData.theme, loggingSettings.redactSensitiveData))
    
    entries.append(.enableRaiseToSpeak(presentationData.theme, mediaInputSettings.enableRaiseToSpeak))
    entries.append(.keepChatNavigationStack(presentationData.theme, experimentalSettings.keepChatNavigationStack))
    entries.append(.clearTips(presentationData.theme))
    if hasLegacyAppData {
        entries.append(.reimport(presentationData.theme))
    }
    entries.append(.resetData(presentationData.theme))
    entries.append(.animatedStickers(presentationData.theme))
    entries.append(.versionInfo(presentationData.theme))
    
    return entries
}

public func debugController(sharedContext: SharedAccountContext, context: AccountContext?, modal: Bool = false) -> ViewController {
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?
    var dismissImpl: (() -> Void)?
    
    let arguments = DebugControllerArguments(sharedContext: sharedContext, context: context, presentController: { controller, arguments in
        presentControllerImpl?(controller, arguments)
    }, pushController: { controller in
        pushControllerImpl?(controller)
    })
    
    let appGroupName = "group.\(Bundle.main.bundleIdentifier!)"
    let maybeAppGroupUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupName)
    
    var hasLegacyAppData = false
    if let appGroupUrl = maybeAppGroupUrl {
        let statusPath = appGroupUrl.path + "/Documents/importcompleted"
        hasLegacyAppData = FileManager.default.fileExists(atPath: statusPath)
    }
    
    let signal = combineLatest(sharedContext.presentationData, sharedContext.accountManager.sharedData(keys: Set([SharedDataKeys.loggingSettings, ApplicationSpecificSharedDataKeys.mediaInputSettings, ApplicationSpecificSharedDataKeys.experimentalUISettings])))
    |> map { presentationData, sharedData -> (ItemListControllerState, (ItemListNodeState<DebugControllerEntry>, DebugControllerEntry.ItemGenerationArguments)) in
        let loggingSettings: LoggingSettings
        if let value = sharedData.entries[SharedDataKeys.loggingSettings] as? LoggingSettings {
            loggingSettings = value
        } else {
            loggingSettings = LoggingSettings.defaultSettings
        }
        
        let mediaInputSettings: MediaInputSettings
        if let value = sharedData.entries[ApplicationSpecificSharedDataKeys.mediaInputSettings] as? MediaInputSettings {
            mediaInputSettings = value
        } else {
            mediaInputSettings = MediaInputSettings.defaultSettings
        }
        
        let experimentalSettings: ExperimentalUISettings = (sharedData.entries[ApplicationSpecificSharedDataKeys.experimentalUISettings] as? ExperimentalUISettings) ?? ExperimentalUISettings.defaultSettings
        
        var leftNavigationButton: ItemListNavigationButton?
        if modal {
            leftNavigationButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Cancel), style: .regular, enabled: true, action: {
                dismissImpl?()
            })
        }
        
        let controllerState = ItemListControllerState(theme: presentationData.theme, title: .text("Debug"), leftNavigationButton: leftNavigationButton, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(entries: debugControllerEntries(presentationData: presentationData, loggingSettings: loggingSettings, mediaInputSettings: mediaInputSettings, experimentalSettings: experimentalSettings, hasLegacyAppData: hasLegacyAppData), style: .blocks)
        
        return (controllerState, (listState, arguments))
    }
    
    
    let controller = ItemListController(sharedContext: sharedContext, state: signal)
    presentControllerImpl = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    dismissImpl = { [weak controller] in
        controller?.dismiss()
    }
    return controller
}
