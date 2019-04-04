import Foundation
import Postbox
import SwiftSignalKit

final class CachedStickerAJpegRepresentation: CachedMediaResourceRepresentation {
    let size: CGSize?
    
    var uniqueId: String {
        if let size = self.size {
            return "sticker-ajpeg-\(Int(size.width))x\(Int(size.height))"
        } else {
            return "sticker-ajpeg"
        }
    }
    
    init(size: CGSize?) {
        self.size = size
    }
    
    func isEqual(to: CachedMediaResourceRepresentation) -> Bool {
        if let to = to as? CachedStickerAJpegRepresentation {
            return self.size == to.size
        } else {
            return false
        }
    }
}

enum CachedScaledImageRepresentationMode: Int32 {
    case fill = 0
    case aspectFit = 1
}

final class CachedScaledImageRepresentation: CachedMediaResourceRepresentation {
    let size: CGSize
    let mode: CachedScaledImageRepresentationMode
    
    var uniqueId: String {
        return "scaled-image-\(Int(self.size.width))x\(Int(self.size.height))-\(self.mode.rawValue)"
    }
    
    init(size: CGSize, mode: CachedScaledImageRepresentationMode) {
        self.size = size
        self.mode = mode
    }
    
    func isEqual(to: CachedMediaResourceRepresentation) -> Bool {
        if let to = to as? CachedScaledImageRepresentation {
            return self.size == to.size && self.mode == to.mode
        } else {
            return false
        }
    }
}

final class CachedVideoFirstFrameRepresentation: CachedMediaResourceRepresentation {
    var uniqueId: String {
        return "first-frame"
    }
    
    func isEqual(to: CachedMediaResourceRepresentation) -> Bool {
        if to is CachedVideoFirstFrameRepresentation {
            return true
        } else {
            return false
        }
    }
}

final class CachedScaledVideoFirstFrameRepresentation: CachedMediaResourceRepresentation {
    let size: CGSize
    
    var uniqueId: String {
        return "scaled-frame-\(Int(self.size.width))x\(Int(self.size.height))"
    }
    
    init(size: CGSize) {
        self.size = size
    }
    
    func isEqual(to: CachedMediaResourceRepresentation) -> Bool {
        if let to = to as? CachedScaledVideoFirstFrameRepresentation {
            return self.size == to.size
        } else {
            return false
        }
    }
}

final class CachedBlurredWallpaperRepresentation: CachedMediaResourceRepresentation {
    var uniqueId: String {
        return "blurred-wallpaper"
    }
    
    func isEqual(to: CachedMediaResourceRepresentation) -> Bool {
        if to is CachedBlurredWallpaperRepresentation {
            return true
        } else {
            return false
        }
    }
}

final class CachedPatternWallpaperMaskRepresentation: CachedMediaResourceRepresentation {
    let size: CGSize?
    
    var uniqueId: String {
        if let size = self.size {
            return "pattern-wallpaper-mask-\(Int(size.width))x\(Int(size.height))"
        } else {
            return "pattern-wallpaper-mask"
        }
    }
    
    init(size: CGSize?) {
        self.size = size
    }
    
    func isEqual(to: CachedMediaResourceRepresentation) -> Bool {
        if let to = to as? CachedPatternWallpaperMaskRepresentation {
            return self.size == to.size
        } else {
            return false
        }
    }
}


final class CachedPatternWallpaperRepresentation: CachedMediaResourceRepresentation {
    let color: Int32
    let intensity: Int32
    
    var uniqueId: String {
        return "pattern-wallpaper-\(self.color)-\(self.intensity)"
    }
    
    init(color: Int32, intensity: Int32) {
        self.color = color
        self.intensity = intensity
    }
    
    func isEqual(to: CachedMediaResourceRepresentation) -> Bool {
        if let to = to as? CachedPatternWallpaperRepresentation {
            return self.color == to.color && self.intensity == intensity
        } else {
            return false
        }
    }
}

final class CachedAlbumArtworkRepresentation: CachedMediaResourceRepresentation {
    let size: CGSize?
    
    var uniqueId: String {
        if let size = self.size {
            return "album-artwork-\(Int(size.width))x\(Int(size.height))"
        } else {
            return "album-artwork"
        }
    }
    
    init(size: CGSize) {
        self.size = size
    }
    
    func isEqual(to: CachedMediaResourceRepresentation) -> Bool {
        if let to = to as? CachedAlbumArtworkRepresentation {
            return self.size == to.size
        } else {
            return false
        }
    }
}
