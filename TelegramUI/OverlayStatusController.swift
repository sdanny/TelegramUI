import Foundation
import Display

import LegacyComponents

enum OverlayStatusControllerType {
    case loading(cancelled: (() -> Void)?)
    case success
    case shieldSuccess(String, Bool)
    case genericSuccess(String)
    case starSuccess(String)
}

private enum OverlayStatusContentController {
    case loading(TGProgressWindowController)
    case progress(TGProgressWindowController)
    case shieldSuccess(TGProxyWindowController, Bool)
    case genericSuccess(TGProxyWindowController)
    case starSuccess(TGProxyWindowController)
    
    var view: UIView {
        switch self {
            case let .loading(controller):
                return controller.view
            case let .progress(controller):
                return controller.view
            case let .shieldSuccess(controller, _):
                return controller.view
            case let .genericSuccess(controller):
                return controller.view
            case let .starSuccess(controller):
                return controller.view
        }
    }
    
    func updateLayout() {
        switch self {
            case let .loading(controller):
                controller.updateLayout()
            case let .progress(controller):
                controller.updateLayout()
            case let .shieldSuccess(controller, _):
                controller.updateLayout()
            case let .genericSuccess(controller):
                controller.updateLayout()
            case let .starSuccess(controller):
                controller.updateLayout()
        }
    }
    
    func show(success: @escaping () -> Void) {
        switch self {
            case let .loading(controller):
                controller.show(true)
            case let .progress(controller):
                controller.dismiss(success: success)
            case let .shieldSuccess(controller, increasedDelay):
                controller.dismiss(success: success, increasedDelay: increasedDelay)
            case let .genericSuccess(controller):
                controller.dismiss(success: success, increasedDelay: false)
            case let .starSuccess(controller):
                controller.dismiss(success: success, increasedDelay: false)
        }
    }
    
    func dismiss(completion: @escaping () -> Void) {
        switch self {
            case let .loading(controller):
                controller.dismiss(true, completion: {
                    completion()
                })
            default:
                completion()
        }
    }
}

private final class OverlayStatusControllerNode: ViewControllerTracingNode {
    private let dismissed: () -> Void
    private let contentController: OverlayStatusContentController
    
    init(theme: PresentationTheme, strings: PresentationStrings, type: OverlayStatusControllerType, dismissed: @escaping () -> Void) {
        self.dismissed = dismissed
        switch type {
            case let .loading(cancelled):
                let controller = TGProgressWindowController(light: theme.actionSheet.backgroundType == .light)!
                controller.cancelled = {
                    cancelled?()
                }
                self.contentController = .loading(controller)
            case .success:
                self.contentController = .progress(TGProgressWindowController(light: theme.actionSheet.backgroundType == .light))
            case let .shieldSuccess(text, increasedDelay):
                self.contentController = .shieldSuccess(TGProxyWindowController(light: theme.actionSheet.backgroundType == .light, text: text, shield: true, star: false), increasedDelay)
            case let .genericSuccess(text):
                self.contentController = .genericSuccess(TGProxyWindowController(light: theme.actionSheet.backgroundType == .light, text: text, shield: false, star: false))
            case let .starSuccess(text):
                self.contentController = .genericSuccess(TGProxyWindowController(light: theme.actionSheet.backgroundType == .light, text: text, shield: false, star: true))
        }
        
        super.init()
        
        self.backgroundColor = nil
        self.isOpaque = false
        
        self.view.addSubview(self.contentController.view)
    }
    
    func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        self.contentController.view.frame = CGRect(origin: CGPoint(), size: layout.size)
        self.contentController.updateLayout()
    }
    
    func begin() {
        self.contentController.show(success: { [weak self] in
            self?.dismissed()
        })
    }
    
    func dismiss(increasedDelay: Bool = false) {
        self.contentController.dismiss(completion: { [weak self] in
            self?.dismissed()
        })
    }
}

final class OverlayStatusController: ViewController {
    private let theme: PresentationTheme
    private let strings: PresentationStrings
    private let type: OverlayStatusControllerType
    
    private var animatedDidAppear = false
    
    private var controllerNode: OverlayStatusControllerNode {
        return self.displayNode as! OverlayStatusControllerNode
    }
    
    init(theme: PresentationTheme, strings: PresentationStrings, type: OverlayStatusControllerType) {
        self.theme = theme
        self.strings = strings
        self.type = type
        
        super.init(navigationBarPresentationData: nil)
        
        self.statusBar.statusBarStyle = .Ignore
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadDisplayNode() {
        self.displayNode = OverlayStatusControllerNode(theme: self.theme, strings: self.strings, type: self.type, dismissed: { [weak self] in
            self?.presentingViewController?.dismiss(animated: false, completion: nil)
        })
        
        self.displayNodeDidLoad()
    }
    
    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        
        self.controllerNode.containerLayoutUpdated(layout, transition: transition)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if !self.animatedDidAppear {
            self.animatedDidAppear = true
            self.controllerNode.begin()
        }
    }
    
    func dismiss() {
        self.controllerNode.dismiss()
    }
}
