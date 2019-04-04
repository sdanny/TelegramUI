import Foundation
import Display
import AsyncDisplayKit
import SwiftSignalKit
import Postbox

enum WallpaperOptionButtonValue {
    case check(Bool)
    case color(Bool, UIColor)
}

final class WallpaperOptionButtonNode: HighlightTrackingButtonNode {
    private let backgroundNode: ASDisplayNode
    private let checkNode: ModernCheckNode
    private let colorNode: ASImageNode
    private let textNode: ASTextNode
    
    private var textSize: CGSize?
    
    private var _value: WallpaperOptionButtonValue
    override var isSelected: Bool {
        get {
            switch self._value {
                case let .check(selected), let .color(selected, _):
                    return selected
            }
        }
        set {
            switch self._value {
                case .check:
                    self._value = .check(newValue)
                case let .color(_, color):
                    self._value = .color(newValue, color)
            }
            self.checkNode.setSelected(newValue, animated: false)
        }
    }
    
    init(title: String, value: WallpaperOptionButtonValue) {
        self._value = value
        
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.backgroundColor = UIColor(rgb: 0x000000, alpha: 0.3)
        self.backgroundNode.cornerRadius = 6.0
        
        self.checkNode = ModernCheckNode(theme: CheckNodeTheme(backgroundColor: .white, strokeColor: .clear, borderColor: .white, hasShadow: false))
        self.checkNode.isUserInteractionEnabled = false
        
        self.colorNode = ASImageNode()
        
        self.textNode = ASTextNode()
        self.textNode.attributedText = NSAttributedString(string: title, font: Font.medium(13), textColor: .white)
        
        super.init()
        
        switch value {
            case let .check(selected):
                self.checkNode.isHidden = false
                self.colorNode.isHidden = true
                self.checkNode.selected = selected
            case let .color(_, color):
                self.checkNode.isHidden = true
                self.colorNode.isHidden = false
                self.colorNode.image = generateFilledCircleImage(diameter: 18.0, color: color)
        }
        
        self.addSubnode(self.backgroundNode)
        self.addSubnode(self.checkNode)
        self.addSubnode(self.colorNode)
        self.addSubnode(self.textNode)
        
        self.highligthedChanged = { [weak self] highlighted in
            if let strongSelf = self {
                if highlighted {
                    strongSelf.backgroundNode.layer.removeAnimation(forKey: "opacity")
                    strongSelf.backgroundNode.alpha = 0.4
                    
                    strongSelf.checkNode.layer.removeAnimation(forKey: "opacity")
                    strongSelf.checkNode.alpha = 0.4
                    
                    strongSelf.colorNode.layer.removeAnimation(forKey: "opacity")
                    strongSelf.colorNode.alpha = 0.4
                    
                    strongSelf.textNode.layer.removeAnimation(forKey: "opacity")
                    strongSelf.textNode.alpha = 0.4
                } else {
                    strongSelf.backgroundNode.alpha = 1.0
                    strongSelf.backgroundNode.layer.animateAlpha(from: 0.4, to: 1.0, duration: 0.2)
                    
                    strongSelf.checkNode.alpha = 1.0
                    strongSelf.checkNode.layer.animateAlpha(from: 0.4, to: 1.0, duration: 0.2)
                    
                    strongSelf.colorNode.alpha = 1.0
                    strongSelf.colorNode.layer.animateAlpha(from: 0.4, to: 1.0, duration: 0.2)
                    
                    strongSelf.textNode.alpha = 1.0
                    strongSelf.textNode.layer.animateAlpha(from: 0.4, to: 1.0, duration: 0.2)
                }
            }
        }
    }
    
    var buttonColor: UIColor = UIColor(rgb: 0x000000, alpha: 0.3) {
        didSet {
            self.backgroundNode.backgroundColor = self.buttonColor
        }
    }
    
    var color: UIColor? {
        get {
            switch self._value {
                case let .color(_, color):
                    return color
                default:
                    return nil
            }
        }
        set {
            if let color = newValue {
                switch self._value {
                    case let .color(selected, _):
                        self._value = .color(selected, color)
                        self.colorNode.image = generateFilledCircleImage(diameter: 18.0, color: color)
                    default:
                        break
                }
            }
        }
    }
    
    func setSelected(_ selected: Bool, animated: Bool = false) {
        self.isSelected = selected
        self.checkNode.setSelected(selected, animated: animated)
    }
    
    func setEnabled(_ enabled: Bool) {
        let alpha: CGFloat = enabled ? 1.0 : 0.3
        self.backgroundNode.alpha = alpha
        self.checkNode.alpha = alpha
        self.colorNode.alpha = alpha
        self.textNode.alpha = alpha
        self.isUserInteractionEnabled = enabled
    }
    
    override func measure(_ constrainedSize: CGSize) -> CGSize {
        let size = self.textNode.measure(constrainedSize)
        self.textSize = size
        return CGSize(width: ceil(size.width) + 52.0, height: 30.0)
    }
    
    override func layout() {
        super.layout()
        
        self.backgroundNode.frame = self.bounds
        
        guard let textSize = self.textSize else {
            return
        }
        
        let checkSize = CGSize(width: 18.0, height: 18.0)
        let spacing: CGFloat = 9.0
        let totalWidth = checkSize.width + spacing + textSize.width
        let origin = floor((self.bounds.width - totalWidth) / 2.0)
        
        self.checkNode.frame = CGRect(origin: CGPoint(x: origin, y: 6.0), size: checkSize)
        self.colorNode.frame = CGRect(origin: CGPoint(x: origin, y: 6.0), size: checkSize)
        
        if let textSize = self.textSize {
            self.textNode.frame = CGRect(x: origin + checkSize.width + spacing, y: 6.0 + UIScreenPixel, width: textSize.width, height: textSize.height)
        }
    }
}

final class WallpaperGalleryDecorationNode: ASDisplayNode {
    private let dismiss: () -> Void
    private let apply: () -> Void
    
//    private var messageNodes: [ListViewItemNode]?
//    private var blurredButtonNode: WallpaperOptionButtonNode?
//    private var motionButtonNode: WallpaperOptionButtonNode?
//    private var toolbarNode: WallpaperGalleryToolbarNode?
    
    init(source: WallpaperListSource, dismiss: @escaping () -> Void, apply: @escaping () -> Void) {
        self.dismiss = dismiss
        self.apply = apply
        
        super.init()
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        if result != self.view {
            return result
        } else {
            return nil
        }
    }
}
