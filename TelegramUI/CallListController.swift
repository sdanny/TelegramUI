import Foundation
import Display
import AsyncDisplayKit
import Postbox
import TelegramCore
import SwiftSignalKit

public enum CallListControllerMode {
    case tab
    case navigation
}

public final class CallListController: ViewController {
    private var controllerNode: CallListControllerNode {
        return self.displayNode as! CallListControllerNode
    }
    
    private let _ready = Promise<Bool>(false)
    override public var ready: Promise<Bool> {
        return self._ready
    }
    
    public var playRecordingPromise = Promise<(Peer, Int64)>()
    
    private let account: Account
    private let mode: CallListControllerMode
    
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?
    
    private let peerViewDisposable = MetaDisposable()
    
    private let segmentedTitleView: ItemListControllerSegmentedTitleView
    
    private var isEmpty: Bool?
    private var editingMode: Bool = false
    
    private let createActionDisposable = MetaDisposable()
    
    public init(account: Account, mode: CallListControllerMode) {
        self.account = account
        self.mode = mode
        self.presentationData = account.telegramApplicationContext.currentPresentationData.with { $0 }
        
        self.segmentedTitleView = ItemListControllerSegmentedTitleView(segments: [self.presentationData.strings.Calls_All, self.presentationData.strings.Calls_Missed], index: 0, color: self.presentationData.theme.rootController.navigationBar.accentTextColor)
        
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        
        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBar.style.style
        
        if case .tab = self.mode {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(image: PresentationResourcesRootController.navigationCallIcon(self.presentationData.theme), style: .plain, target: self, action: #selector(self.callPressed))
            
            let icon: UIImage?
            if (useSpecialTabBarIcons()) {
                icon = UIImage(bundleImageName: "Chat List/Tabs/NY/IconCalls")
            } else {
                icon = UIImage(bundleImageName: "Chat List/Tabs/IconCalls")
            }
            
            self.tabBarItem.title = "Records"//self.presentationData.strings.Calls_TabTitle
            self.tabBarItem.image = icon
            self.tabBarItem.selectedImage = icon
        }
        
        self.segmentedTitleView.indexUpdated = { [weak self] index in
            if let strongSelf = self {
                strongSelf.controllerNode.updateType(index == 0 ? .all : .missed)
            }
        }
        
        self.presentationDataDisposable = (account.telegramApplicationContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            if let strongSelf = self {
                let previousTheme = strongSelf.presentationData.theme
                let previousStrings = strongSelf.presentationData.strings
                
                strongSelf.presentationData = presentationData
                
                if previousTheme !== presentationData.theme || previousStrings !== presentationData.strings {
                    strongSelf.updateThemeAndStrings()
                }
            }
        })
        
        self.scrollToTop = { [weak self] in
            self?.controllerNode.scrollToLatest()
        }
        
        self.navigationItem.titleView = self.segmentedTitleView
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.createActionDisposable.dispose()
        self.presentationDataDisposable?.dispose()
        self.peerViewDisposable.dispose()
    }
    
    private func updateThemeAndStrings() {
        let index = self.segmentedTitleView.index
        self.segmentedTitleView.segments = [self.presentationData.strings.Calls_All, self.presentationData.strings.Calls_Missed]
        self.segmentedTitleView.color = self.presentationData.theme.rootController.navigationBar.accentTextColor
        self.segmentedTitleView.index = index
            
        self.tabBarItem.title = "Records" //self.presentationData.strings.Calls_TabTitle
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Back, style: .plain, target: nil, action: nil)
        switch self.mode {
            case .tab:
                if let isEmpty = self.isEmpty, isEmpty {
                } else {
                    if self.editingMode {
                        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Done, style: .done, target: self, action: #selector(self.donePressed))
                    } else {
                        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Edit, style: .plain, target: self, action: #selector(self.editPressed))
                    }
                }
                
                self.navigationItem.rightBarButtonItem = UIBarButtonItem(image: PresentationResourcesRootController.navigationCallIcon(self.presentationData.theme), style: .plain, target: self, action: #selector(self.callPressed))
            case .navigation:
                if self.editingMode {
                    self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Done, style: .done, target: self, action: #selector(self.donePressed))
                } else {
                    self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Edit, style: .plain, target: self, action: #selector(self.editPressed))
                }
        }
        
        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBar.style.style
        self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationData: self.presentationData))
        
        if self.isNodeLoaded {
            self.controllerNode.updateThemeAndStrings(theme: self.presentationData.theme, strings: self.presentationData.strings, dateTimeFormat: self.presentationData.dateTimeFormat, disableAnimations: self.presentationData.disableAnimations)
        }
        
    }
    
    override public func loadDisplayNode() {
        self.displayNode = CallListControllerNode(account: self.account, mode: self.mode, presentationData: self.presentationData, call: { [weak self] peerId in
            guard let self = self else { return }
            self.call(peerId)
        }, playRecording: { [weak self] peerId, callId in
            guard let self = self else { return }
            let _ = (self.account.postbox.loadedPeerWithId(peerId)
                |> take(1)
                |> deliverOnMainQueue).start(next: { [weak self] peer in
                    guard let self = self else { return }
                    self.playRecordingPromise.set(.single((peer, callId)))
                })
        }, emptyStateUpdated: { [weak self] empty in
            if let strongSelf = self {
                if empty != strongSelf.isEmpty {
                    strongSelf.isEmpty = empty
                    
                    if empty {
                        switch strongSelf.mode {
                            case .tab:
                                strongSelf.navigationItem.setLeftBarButton(nil, animated: true)
                            case .navigation:
                                strongSelf.navigationItem.setRightBarButton(nil, animated: true)
                        }
                    } else {
                        switch strongSelf.mode {
                            case .tab:
                                if strongSelf.editingMode {
                                    strongSelf.navigationItem.leftBarButtonItem = UIBarButtonItem(title: strongSelf.presentationData.strings.Common_Done, style: .done, target: strongSelf, action: #selector(strongSelf.donePressed))
                                } else {
                                    strongSelf.navigationItem.leftBarButtonItem = UIBarButtonItem(title: strongSelf.presentationData.strings.Common_Edit, style: .plain, target: strongSelf, action: #selector(strongSelf.editPressed))
                                }
                            case .navigation:
                                if strongSelf.editingMode {
                                    strongSelf.navigationItem.rightBarButtonItem = UIBarButtonItem(title: strongSelf.presentationData.strings.Common_Done, style: .done, target: strongSelf, action: #selector(strongSelf.donePressed))
                                } else {
                                    strongSelf.navigationItem.rightBarButtonItem = UIBarButtonItem(title: strongSelf.presentationData.strings.Common_Edit, style: .plain, target: strongSelf, action: #selector(strongSelf.editPressed))
                                }
                        }
                    }
                }
            }
        })
        self._ready.set(self.controllerNode.ready)
        self.displayNodeDidLoad()
    }
    
    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        
        self.controllerNode.containerLayoutUpdated(layout, navigationBarHeight: self.navigationHeight, transition: transition)
    }
    
    @objc func callPressed() {
        let controller = ContactSelectionController(account: self.account, title: { $0.Calls_NewCall })
        self.createActionDisposable.set((controller.result
            |> take(1)
            |> deliverOnMainQueue).start(next: { [weak controller, weak self] peer in
                controller?.dismissSearch()
                if let strongSelf = self, let contactPeer = peer, case let .peer(peer, _) = contactPeer {
                    strongSelf.call(peer.id, began: {
                        if let strongSelf = self {
                            if let hasOngoingCall = strongSelf.account.telegramApplicationContext.hasOngoingCall {
                                let _ = (hasOngoingCall
                                    |> filter { $0 }
                                    |> timeout(1.0, queue: Queue.mainQueue(), alternate: .single(true))
                                    |> delay(0.5, queue: Queue.mainQueue())
                                    |> deliverOnMainQueue).start(next: { _ in
                                        if let _ = self, let controller = controller, let navigationController = controller.navigationController as? NavigationController {
                                            if navigationController.viewControllers.last === controller {
                                                let _ = navigationController.popViewController(animated: true)
                                            }
                                        }
                                    })
                            }
                        }
                    })
                }
            }))
        (self.navigationController as? NavigationController)?.pushViewController(controller)
    }
    
    @objc func editPressed() {
        self.editingMode = true
        switch self.mode {
            case .tab:
                self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Done, style: .done, target: self, action: #selector(self.donePressed))
            case .navigation:
                self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Done, style: .done, target: self, action: #selector(self.donePressed))
        }
        
        self.controllerNode.updateState { state in
            return state.withUpdatedEditing(true)
        }
    }
    
    @objc func donePressed() {
        self.editingMode = false
        switch self.mode {
            case .tab:
                self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Edit, style: .plain, target: self, action: #selector(self.editPressed))
            case .navigation:
                self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Edit, style: .plain, target: self, action: #selector(self.editPressed))
        }
        
        self.controllerNode.updateState { state in
            return state.withUpdatedEditing(false)
        }
    }
    
    private func call(_ peerId: PeerId, began: (() -> Void)? = nil) {
        self.peerViewDisposable.set((self.account.viewTracker.peerView(peerId)
            |> take(1)
            |> deliverOnMainQueue).start(next: { [weak self] view in
            if let strongSelf = self {
                guard let peer = peerViewMainPeer(view) else {
                    return
                }
                
                if let cachedUserData = view.cachedData as? CachedUserData, cachedUserData.callsPrivate {
                    let presentationData = strongSelf.account.telegramApplicationContext.currentPresentationData.with { $0 }
                    
                    strongSelf.present(standardTextAlertController(theme: AlertControllerTheme(presentationTheme: presentationData.theme), title: presentationData.strings.Call_ConnectionErrorTitle, text: presentationData.strings.Call_PrivacyErrorMessage(peer.compactDisplayTitle).0, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
                    return
                }
            
                let callResult = strongSelf.account.telegramApplicationContext.callManager?.requestCall(peerId: peerId, endCurrentIfAny: false)
                if let callResult = callResult {
                    if case let .alreadyInProgress(currentPeerId) = callResult {
                        if currentPeerId == peerId {
                            began?()
                            strongSelf.account.telegramApplicationContext.navigateToCurrentCall?()
                        } else {
                            let presentationData = strongSelf.presentationData
                            let _ = (strongSelf.account.postbox.transaction { transaction -> (Peer?, Peer?) in
                                return (transaction.getPeer(peerId), transaction.getPeer(currentPeerId))
                                } |> deliverOnMainQueue).start(next: { [weak self] peer, current in
                                    if let strongSelf = self, let peer = peer, let current = current {
                                        strongSelf.present(standardTextAlertController(theme: AlertControllerTheme(presentationTheme: presentationData.theme), title: presentationData.strings.Call_CallInProgressTitle, text: presentationData.strings.Call_CallInProgressMessage(current.compactDisplayTitle, peer.compactDisplayTitle).0, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_Cancel, action: {}), TextAlertAction(type: .genericAction, title: presentationData.strings.Common_OK, action: {
                                            if let strongSelf = self {
                                                let _ = strongSelf.account.telegramApplicationContext.callManager?.requestCall(peerId: peerId, endCurrentIfAny: true)
                                                began?()
                                            }
                                        })]), in: .window(.root))
                                    }
                                })
                        }
                    } else {
                        began?()
                    }
                }
            }
        }))
    }
}
