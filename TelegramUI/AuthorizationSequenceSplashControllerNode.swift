import Foundation
import AsyncDisplayKit
import Display

final class AuthorizationSequenceSplashControllerNode: ASDisplayNode {
    init(theme: PresentationTheme) {
        super.init()
        
        self.setViewBlock({
            return UITracingLayerView()
        })
        
        self.backgroundColor = theme.list.plainBackgroundColor
        self.view.disablesInteractiveTransitionGestureRecognizer = true
    }
    
    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
    }
}
