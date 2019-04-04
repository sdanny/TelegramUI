import Foundation
import Display
import Postbox
import TelegramCore
import SwiftSignalKit

public final class TelegramRootController: NavigationController {
    private let context: AccountContext
    
    public var rootTabController: TabBarController?
    
    public var contactsController: ContactsController?
    public var callListController: CallListController?
//    public var chatListController: ChatListController?
    public var accountSettingsController: ViewController?
    public var recordingController: RecordingController?
    
    private var permissionsDisposable: Disposable?
    private var presentationDataDisposable: Disposable?
    private var recordingsSetupDisposable: Disposable?
    private var playRecordingDisposable: Disposable?
    private var presentationData: PresentationData
    
    public init(context: AccountContext) {
        self.context = context
        
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        
        super.init(mode: .automaticMasterDetail, theme: NavigationControllerTheme(presentationTheme: self.presentationData.theme))
        
        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            if let strongSelf = self {
                let previousTheme = strongSelf.presentationData.theme
                strongSelf.presentationData = presentationData
                if previousTheme !== presentationData.theme {
                    strongSelf.rootTabController?.updateTheme(navigationBarPresentationData: NavigationBarPresentationData(presentationData: presentationData), theme: TabBarControllerTheme(rootControllerTheme: presentationData.theme))
                    strongSelf.rootTabController?.statusBar.statusBarStyle = presentationData.theme.rootController.statusBar.style.style
                }
            }
        })
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.permissionsDisposable?.dispose()
        self.presentationDataDisposable?.dispose()
        self.recordingsSetupDisposable?.dispose()
        self.playRecordingDisposable?.dispose()
    }
    
    public func addRootControllers(showCallsTab: Bool) {
        let tabBarController = TabBarController(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData), theme: TabBarControllerTheme(rootControllerTheme: self.presentationData.theme))
//        let chatListController = ChatListController(account: self.account, groupId: nil, controlsHistoryPreload: true)
        let callListController = CallListController(context: self.context, mode: .tab)
        let recordingController = RecordingController(context: self.context)
        
        var controllers: [ViewController] = []
        
        let contactsController = ContactsController(context: self.context)
        contactsController.switchToChatsController = {  [weak self] in
            self?.openChatsController(activateSearch: false)
        }
        controllers.append(contactsController)
        
        controllers.append(callListController)
//        controllers.append(chatListController)
        
        let restoreSettignsController = self.context.sharedContext.switchingData.settingsController
        restoreSettignsController?.updateContext(context: self.context)
        self.context.sharedContext.switchingData = (nil, nil, nil)
        
        let accountSettingsController = restoreSettignsController ?? settingsController(context: self.context, accountManager: context.sharedContext.accountManager)
        controllers.append(accountSettingsController)
        
        tabBarController.setControllers(controllers, selectedIndex: controllers.count - 2)
        insertRecordingSubnode(controller: recordingController, intoTabBarController: tabBarController)
        
        self.contactsController = contactsController
        self.callListController = callListController
        self.recordingController = recordingController
//        self.chatListController = chatListController
        self.accountSettingsController = accountSettingsController
        self.rootTabController = tabBarController
        self.pushViewController(tabBarController, animated: false)
        
        subscribePlayRecordings(withController: callListController)
    }
    
    private func subscribePlayRecordings(withController controller: CallListController) {
        playRecordingDisposable = callListController?.playRecordingPromise.get().start(next: { [weak self] (peer, callId) in
            guard let self = self,
                let rootController = self.rootTabController,
                let recordingController = self.recordingController else { return }
            let width = rootController.displayNode.bounds.width
            recordingController.controllerNode.contentSize = CGSize(width: width, height: 64)
            recordingController.update(callId: callId, peer: peer)
            recordingController.play()
        })
    }
    
    private func insertRecordingSubnode(controller: RecordingController, intoTabBarController barController: TabBarController) {
        let readiness = combineLatest(controller.ready.get(), barController.ready.get())
            |> filter { $0 && $1 }
            |> take(1)
            |> deliverOnMainQueue
        recordingsSetupDisposable = readiness.start(next: { _, _ in
            let node = barController.displayNode
            let subnode = controller.controllerNode!
            node.addSubnode(subnode)
            let bounds = UIScreen.main.bounds
            let height: CGFloat = 64
            subnode.frame = CGRect(origin: CGPoint(x: 0, y: bounds.height - 50 - height), size: CGSize(width: bounds.width, height: height))
        })
    }
    
    public func updateRootControllers(showCallsTab: Bool) {
        guard let rootTabController = self.rootTabController else {
            return
        }
        var controllers: [ViewController] = []
        controllers.append(self.contactsController!)
        controllers.append(self.callListController!)
//        controllers.append(self.chatListController!)
        controllers.append(self.accountSettingsController!)
        
        rootTabController.setControllers(controllers, selectedIndex: nil)
    }
    
    public func openChatsController(activateSearch: Bool) {
        guard let rootTabController = self.rootTabController else {
            return
        }
        
        if activateSearch {
            self.popToRoot(animated: false)
        }
        
        if let index = rootTabController.controllers.index(where: { $0 is ChatListController}) {
            rootTabController.selectedIndex = index
        }
    }
    
    public func openRootCompose() {
//        self.chatListController?.composePressed()
    }
    
    public func openRootCamera() {
        guard let controller = self.viewControllers.last as? ViewController else {
            return
        }
        controller.view.endEditing(true)
        presentedLegacyShortcutCamera(context: self.context, saveCapturedMedia: false, saveEditedPhotos: false, mediaGrouping: true, parentController: controller)
    }
}
