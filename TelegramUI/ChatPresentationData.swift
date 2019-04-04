import Foundation
import UIKit
import TelegramCore

extension PresentationFontSize {
    var baseDisplaySize: CGFloat {
        switch self {
            case .extraSmall:
                return 14.0
            case .small:
                return 15.0
            case .medium:
                return 16.0
            case .regular:
                return 17.0
            case .large:
                return 19.0
            case .extraLarge:
                return 23.0
            case .extraLargeX2:
                return 26.0
        }
    }
}

extension TelegramWallpaper {
    var isEmpty: Bool {
        switch self {
            case .builtin, .image:
                return false
            case let .file(file):
                if file.isPattern, file.settings.color == 0xffffff {
                    return true
                } else {
                    return false
                }
            case let .color(color):
                return color == 0xffffff
        }
    }
    var isBuiltin: Bool {
        switch self {
            case .builtin:
                return true
            default:
                return false
        }
    }
}

public final class ChatPresentationThemeData: Equatable {
    public let theme: PresentationTheme
    public let wallpaper: TelegramWallpaper
    
    public init(theme: PresentationTheme, wallpaper: TelegramWallpaper) {
        self.theme = theme
        self.wallpaper = wallpaper
    }
    
    public static func ==(lhs: ChatPresentationThemeData, rhs: ChatPresentationThemeData) -> Bool {
        return lhs.theme === rhs.theme && lhs.wallpaper == rhs.wallpaper
    }
}

public final class ChatPresentationData {
    let theme: ChatPresentationThemeData
    let fontSize: PresentationFontSize
    let strings: PresentationStrings
    let dateTimeFormat: PresentationDateTimeFormat
    let nameDisplayOrder: PresentationPersonNameOrder
    let disableAnimations: Bool
    
    let messageFont: UIFont
    let messageEmojiFont1: UIFont
    let messageEmojiFont2: UIFont
    let messageEmojiFont3: UIFont
    let messageBoldFont: UIFont
    let messageItalicFont: UIFont
    let messageFixedFont: UIFont
    
    init(theme: ChatPresentationThemeData, fontSize: PresentationFontSize, strings: PresentationStrings, dateTimeFormat: PresentationDateTimeFormat, nameDisplayOrder: PresentationPersonNameOrder, disableAnimations: Bool) {
        self.theme = theme
        self.fontSize = fontSize
        self.strings = strings
        self.dateTimeFormat = dateTimeFormat
        self.nameDisplayOrder = nameDisplayOrder
        self.disableAnimations = disableAnimations
        
        let baseFontSize = fontSize.baseDisplaySize
        self.messageFont = UIFont.systemFont(ofSize: baseFontSize)
        self.messageEmojiFont1 = UIFont.systemFont(ofSize: ceil(baseFontSize * 2.94))
        self.messageEmojiFont2 = UIFont.systemFont(ofSize: ceil(baseFontSize * 2.29))
        self.messageEmojiFont3 = UIFont.systemFont(ofSize: ceil(baseFontSize * 1.64))
        self.messageBoldFont = UIFont.boldSystemFont(ofSize: baseFontSize)
        self.messageItalicFont = UIFont.italicSystemFont(ofSize: baseFontSize)
        self.messageFixedFont = UIFont(name: "Menlo-Regular", size: baseFontSize - 1.0) ?? UIFont.systemFont(ofSize: baseFontSize)
    }
}
