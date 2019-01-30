import Foundation
import Display

struct PresentationResourcesCallList {
    static func outgoingIcon(_ theme: PresentationTheme) -> UIImage? {
        return theme.image(PresentationResourceKey.callListOutgoingIcon.rawValue, { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Call List/OutgoingIcon"), color: theme.list.disclosureArrowColor)
        })
    }
    
    static func infoButton(_ theme: PresentationTheme) -> UIImage? {
        return theme.image(PresentationResourceKey.callListInfoButton.rawValue, { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Call List/InfoButton"), color: theme.list.itemAccentColor)
        })
    }
    
    static func playButton(_ theme: PresentationTheme) -> UIImage? {
        return theme.image(PresentationResourceKey.callListPlayButton.rawValue, { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Call List/PlayButton"), color: theme.list.itemAccentColor)
        })
    }
}
