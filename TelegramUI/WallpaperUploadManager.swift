import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit

private extension TelegramWallpaper {
    var mainResource: MediaResource? {
        switch self {
            case let .image(representations, _):
                return largestImageRepresentation(representations)?.resource
            case let .file(file):
                return file.file.resource
            default:
                return nil
        }
    }
}

private final class WallpaperUploadContext {
    let wallpaper: TelegramWallpaper
    private let disposable: Disposable
    
    init(wallpaper: TelegramWallpaper, disposable: Disposable) {
        self.wallpaper = wallpaper
        self.disposable = disposable
    }
    
    deinit {
        self.disposable.dispose()
    }
}

private func areMediaResourcesEqual(_ lhs: MediaResource?, _ rhs: MediaResource?) -> Bool {
    if let lhs = lhs, let rhs = rhs {
        return lhs.isEqual(to: rhs)
    } else {
        return false
    }
}

enum WallpaperUploadManagerStatus {
    case none
    case uploading(TelegramWallpaper, Float)
    case uploaded(TelegramWallpaper, TelegramWallpaper)
    
    var wallpaper: TelegramWallpaper? {
        switch self {
            case let .uploading(wallpaper, _), let .uploaded(wallpaper, _):
                return wallpaper
            default:
                return nil
        }
    }
}

final class WallpaperUploadManager {
    private let sharedContext: SharedAccountContext
    private let account: Account
    private var context: WallpaperUploadContext?
    
    private let presentationDataDisposable = MetaDisposable()
    private var currentPresentationData: PresentationData?
    
    private let statePromise = Promise<WallpaperUploadManagerStatus>(.none)
    
    init(sharedContext: SharedAccountContext, account: Account, presentationData: Signal<PresentationData, NoError>) {
        self.sharedContext = sharedContext
        self.account = account
        self.presentationDataDisposable.set(presentationData.start(next: { [weak self] presentationData in
            if let strongSelf = self {
                strongSelf.presentationDataUpdated(presentationData)
            }
        }))
    }
    
    deinit {
        self.presentationDataDisposable.dispose()
    }
    
    func stateSignal() -> Signal<WallpaperUploadManagerStatus, NoError> {
        return self.statePromise.get()
    }
    
    func presentationDataUpdated(_ presentationData: PresentationData) {
        let previousPresentationData = self.currentPresentationData
        self.currentPresentationData = presentationData
        
        let currentWallpaper = presentationData.chatWallpaper
        
        if previousPresentationData?.chatWallpaper != currentWallpaper {
            if case .image = presentationData.chatWallpaper, let currentResource = currentWallpaper.mainResource {
                if areMediaResourcesEqual(self.context?.wallpaper.mainResource, currentResource) {
                } else {
                    let disposable = MetaDisposable()
                    self.context = WallpaperUploadContext(wallpaper: currentWallpaper, disposable: disposable)
                    
                    let statePromise = Promise<WallpaperUploadManagerStatus>(.uploading(currentWallpaper, 0.0))
                    self.statePromise.set(statePromise.get())
                    
                    let sharedContext = self.sharedContext
                    let account = self.account
                    
                    let uploadSignal = uploadWallpaper(account: account, resource: currentResource, settings: currentWallpaper.settings ?? WallpaperSettings())
                    |> map { result -> UploadWallpaperStatus in
                        switch result {
                            case let .complete(wallpaper):
                                if case let .file(_, _, _, _, _, _, _, file, _) = wallpaper {
                                    sharedContext.accountManager.mediaBox.moveResourceData(from: currentResource.id, to: file.resource.id)
                                    account.postbox.mediaBox.moveResourceData(from: currentResource.id, to: file.resource.id)
                                }
                            default:
                                break
                        }
                        return result
                    }
                    
                    disposable.set(uploadSignal.start(next: { [weak self] status in
                        guard let strongSelf = self else {
                            return
                        }
                        if case let .complete(wallpaper) = status {
                            let updateWallpaper: (TelegramWallpaper) -> Void = { wallpaper in
                                if let resource = wallpaper.mainResource {
                                    let _ = account.postbox.mediaBox.cachedResourceRepresentation(resource, representation: CachedScaledImageRepresentation(size: CGSize(width: 720.0, height: 720.0), mode: .aspectFit), complete: true, fetch: true).start(completed: {})
                                    let _ = sharedContext.accountManager.mediaBox.cachedResourceRepresentation(resource, representation: CachedScaledImageRepresentation(size: CGSize(width: 720.0, height: 720.0), mode: .aspectFit), complete: true, fetch: true).start(completed: {})
                                }
                                
                                if strongSelf.currentPresentationData?.theme.name == presentationData.theme.name {
                                    let _ = (updatePresentationThemeSettingsInteractively(accountManager: sharedContext.accountManager, { current in
                                        let updatedWallpaper: TelegramWallpaper
                                        if let currentSettings = current.chatWallpaper.settings {
                                            updatedWallpaper = wallpaper.withUpdatedSettings(currentSettings)
                                        } else {
                                            updatedWallpaper = wallpaper
                                        }
                                        
                                        var themeSpecificChatWallpapers = current.themeSpecificChatWallpapers
                                        themeSpecificChatWallpapers[current.theme.index] = updatedWallpaper
                                        return PresentationThemeSettings(chatWallpaper: updatedWallpaper, theme: current.theme, themeAccentColor: current.themeAccentColor, themeSpecificChatWallpapers: themeSpecificChatWallpapers, fontSize: current.fontSize, automaticThemeSwitchSetting: current.automaticThemeSwitchSetting, disableAnimations: current.disableAnimations)
                                    })).start()
                                }
                            }
                            
                            if case let .file(_, _, _, _, _, _, _, file, settings) = wallpaper, settings.blur {
                                let _ = account.postbox.mediaBox.cachedResourceRepresentation(file.resource, representation: CachedBlurredWallpaperRepresentation(), complete: true, fetch: true).start(completed: {
                                })
                                let _ = sharedContext.accountManager.mediaBox.cachedResourceRepresentation(file.resource, representation: CachedBlurredWallpaperRepresentation(), complete: true, fetch: true).start(completed: {
                                    updateWallpaper(wallpaper)
                                })
                            } else {
                                updateWallpaper(wallpaper)
                            }
                            
                            statePromise.set(.single(.uploaded(currentWallpaper, wallpaper)))
                        } else if case let .progress(progress) = status {
                            statePromise.set(.single(.uploading(currentWallpaper, progress)))
                        }
                    }))
                }
            } else if previousPresentationData?.theme.name == presentationData.theme.name {
                self.context = nil
            }
        }
    }
}
