import Foundation
import Display
import AsyncDisplayKit
import TelegramCore
import SwiftSignalKit
import Postbox

final class ChannelStatsController: ViewController {
    private var controllerNode: ChannelStatsControllerNode {
        return self.displayNode as! ChannelStatsControllerNode
    }
    
    private let context: AccountContext
    private let url: String
    private let peerId: PeerId
    
    private var presentationData: PresentationData
    
    init(context: AccountContext, url: String, peerId: PeerId) {
        self.context = context
        self.url = url
        self.peerId = peerId
        
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        
        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBar.style.style

        self.navigationItem.title = self.presentationData.strings.ChannelInfo_Stats
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func closePressed() {
        self.dismiss()
    }
    
    override func loadDisplayNode() {
        self.displayNode = ChannelStatsControllerNode(context: self.context, presentationData: self.presentationData, peerId: self.peerId, url: self.url, present: { [weak self] c, a in
            self?.present(c, in: .window(.root), with: a)
        }, updateActivity: { [weak self] value in
            guard let strongSelf = self else {
                return
            }
            if value {
                strongSelf.navigationItem.rightBarButtonItem = UIBarButtonItem(customDisplayNode: ProgressNavigationButtonNode(theme: strongSelf.presentationData.theme))
            } else {
                strongSelf.navigationItem.rightBarButtonItem = nil
            }
        })
    }
    
    override func dismiss(completion: (() -> Void)? = nil) {
        self.controllerNode.animateOut(completion: { [weak self] in
            self?.presentingViewController?.dismiss(animated: false, completion: nil)
            completion?()
        })
    }
    
    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        
        self.controllerNode.containerLayoutUpdated(layout, navigationBarHeight: self.navigationHeight, transition: transition)
    }
    
    override var presentationController: UIPresentationController? {
        get {
            return nil
        } set(value) {
            
        }
    }
}
