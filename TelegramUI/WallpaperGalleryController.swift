import Foundation
import Display
import QuickLook
import Postbox
import SwiftSignalKit
import AsyncDisplayKit
import TelegramCore
import Photos

enum WallpaperListType {
    case wallpapers(WallpaperPresentationOptions?)
    case colors
}

enum WallpaperListSource {
    case list(wallpapers: [TelegramWallpaper], central: TelegramWallpaper, type: WallpaperListType)
    case wallpaper(TelegramWallpaper, WallpaperPresentationOptions?, UIColor?, Int32?, Message?)
    case slug(String, TelegramMediaFile?, WallpaperPresentationOptions?, UIColor?, Int32?, Message?)
    case asset(PHAsset)
    case contextResult(ChatContextResult)
    case customColor(Int32?)
}

private func areMessagesEqual(_ lhsMessage: Message?, _ rhsMessage: Message?) -> Bool {
    if lhsMessage == nil && rhsMessage == nil {
        return true
    }
    guard let lhsMessage = lhsMessage, let rhsMessage = rhsMessage else {
        return false
    }
    if lhsMessage.stableVersion != rhsMessage.stableVersion {
        return false
    }
    if lhsMessage.id != rhsMessage.id || lhsMessage.flags != rhsMessage.flags {
        return false
    }
    return true
}

enum WallpaperGalleryEntry: Equatable {
    case wallpaper(TelegramWallpaper, Message?)
    case asset(PHAsset)
    case contextResult(ChatContextResult)
    
    public static func ==(lhs: WallpaperGalleryEntry, rhs: WallpaperGalleryEntry) -> Bool {
        switch lhs {
            case let .wallpaper(lhsWallpaper, lhsMessage):
                if case let .wallpaper(rhsWallpaper, rhsMessage) = rhs, lhsWallpaper == rhsWallpaper, areMessagesEqual(lhsMessage, rhsMessage) {
                    return true
                } else {
                    return false
                }
            case let .asset(lhsAsset):
                if case let .asset(rhsAsset) = rhs, lhsAsset.localIdentifier == rhsAsset.localIdentifier {
                    return true
                } else {
                    return false
                }
            case let .contextResult(lhsResult):
                if case let .contextResult(rhsResult) = rhs, lhsResult.id == rhsResult.id {
                    return true
                } else {
                    return false
                }
        }
    }
}

class WallpaperGalleryOverlayNode: ASDisplayNode {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        if result != self.view {
            return result
        } else {
            return nil
        }
    }
}

class WallpaperGalleryControllerNode: GalleryControllerNode {
    override func updateDistanceFromEquilibrium(_ value: CGFloat) {
        guard let itemNode = self.pager.centralItemNode() as? WallpaperGalleryItemNode else {
            return
        }
        
        itemNode.updateDismissTransition(value)
    }
}

private func updatedFileWallpaper(wallpaper: TelegramWallpaper, color: UIColor?, intensity: Int32?) -> TelegramWallpaper {
    if case let .file(file) = wallpaper {
        return updatedFileWallpaper(id: file.id, accessHash: file.accessHash, slug: file.slug, file: file.file, color: color, intensity: intensity)
    } else {
        return wallpaper
    }
}

private func updatedFileWallpaper(id: Int64? = nil, accessHash: Int64? = nil, slug: String, file: TelegramMediaFile, color: UIColor?, intensity: Int32?) -> TelegramWallpaper {
    let isPattern = file.mimeType == "image/png"
    var colorValue: Int32?
    var intensityValue: Int32?
    if let color = color {
        colorValue = Int32(bitPattern: color.rgb)
        intensityValue = intensity
    } else {
        colorValue = 0xd6e2ee
        intensityValue = 50
    }
    
    return .file(id: id ?? 0, accessHash: accessHash ?? 0, isCreator: false, isDefault: false, isPattern: isPattern, isDark: false, slug: slug, file: file, settings: WallpaperSettings(blur: false, motion: false, color: colorValue, intensity: intensityValue))
}

class WallpaperGalleryController: ViewController {
    private var galleryNode: GalleryControllerNode {
        return self.displayNode as! GalleryControllerNode
    }
    
    private let context: AccountContext
    private let source: WallpaperListSource
    var apply: ((WallpaperGalleryEntry, WallpaperPresentationOptions, CGRect?) -> Void)?
    
    private let _ready = Promise<Bool>()
    override var ready: Promise<Bool> {
        return self._ready
    }
    private var didSetReady = false
    
    private let disposable = MetaDisposable()
    
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?
    
    private var initialOptions: WallpaperPresentationOptions?
    
    private var initialEntries: [WallpaperGalleryEntry] = []
    private var entries: [WallpaperGalleryEntry] = []
    private var centralEntryIndex: Int?
    private var previousCentralEntryIndex: Int?
    
    private let centralItemSubtitle = Promise<String?>()
    private let centralItemStatus = Promise<MediaResourceStatus>()
    private let centralItemAction = Promise<UIBarButtonItem?>()
    private let centralItemAttributesDisposable = DisposableSet();
    
    private var validLayout: (ContainerViewLayout, CGFloat)?
    
    private var overlayNode: WallpaperGalleryOverlayNode?
    private var messageNodes: [ListViewItemNode]?
    private var toolbarNode: WallpaperGalleryToolbarNode?
    private var colorPanelNode: WallpaperColorPanelNode?
    private var patternPanelNode: WallpaperPatternPanelNode?
    
    private var colorPanelEnabled = false
    private var patternPanelEnabled = false
    
    init(context: AccountContext, source: WallpaperListSource) {
        self.context = context
        self.source = source
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: presentationData))
        
        self.title = self.presentationData.strings.WallpaperPreview_Title
        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBar.style.style
        self.supportedOrientations = ViewControllerSupportedOrientations(regularSize: .all, compactSize: .portrait)
        
        var entries: [WallpaperGalleryEntry] = []
        var centralEntryIndex: Int?
        
        switch source {
            case let .list(wallpapers, central, type):
                entries = wallpapers.map { .wallpaper($0, nil) }
                centralEntryIndex = wallpapers.index(of: central)!
                
                if case let .wallpapers(wallpaperOptions) = type, let options = wallpaperOptions {
                    self.initialOptions = options
                }
            case let .slug(slug, file, options, color, intensity, message):
                if let file = file {
                    let wallpaper = updatedFileWallpaper(slug: slug, file: file, color: color, intensity: intensity)
                    entries = [.wallpaper(wallpaper, message)]
                    centralEntryIndex = 0
                    self.initialOptions = options
                }
            case let .wallpaper(wallpaper, options, color, intensity, message):
                let wallpaper = updatedFileWallpaper(wallpaper: wallpaper, color: color, intensity: intensity)
                entries = [.wallpaper(wallpaper, message)]
                centralEntryIndex = 0
                self.initialOptions = options
            case let .asset(asset):
                entries = [.asset(asset)]
                centralEntryIndex = 0
            case let .contextResult(result):
                entries = [.contextResult(result)]
                centralEntryIndex = 0
            case let .customColor(color):
                self.colorPanelEnabled = true
                let initialColor = color ?? 0x000000
                entries = [.wallpaper(.color(initialColor), nil)]
                centralEntryIndex = 0
        }
        
        self.entries = entries
        self.initialEntries = entries
        self.centralEntryIndex = centralEntryIndex
        
        self.presentationDataDisposable = (context.sharedContext.presentationData
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
       
        self.centralItemAttributesDisposable.add(self.centralItemSubtitle.get().start(next: { [weak self] subtitle in
            if let strongSelf = self {
                if let subtitle = subtitle {
                    let titleView = CounterContollerTitleView(theme: strongSelf.presentationData.theme)
                    titleView.title = CounterContollerTitle(title: strongSelf.presentationData.strings.WallpaperPreview_Title, counter: subtitle)
                    strongSelf.navigationItem.titleView = titleView
                    strongSelf.title = nil
                } else {
                    strongSelf.navigationItem.titleView = nil
                    strongSelf.title = strongSelf.presentationData.strings.WallpaperPreview_Title
                }
            }
        }))
        
        self.centralItemAttributesDisposable.add(self.centralItemStatus.get().start(next: { [weak self] status in
            if let strongSelf = self {
                let enabled: Bool
                switch status {
                    case .Local:
                        enabled = true
                    default:
                        enabled = false
                }
                strongSelf.toolbarNode?.setDoneEnabled(enabled)
            }
        }))
        
        self.centralItemAttributesDisposable.add(self.centralItemAction.get().start(next: { [weak self] barButton in
            if let strongSelf = self {
                strongSelf.navigationItem.rightBarButtonItem = barButton
            }
        }))
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.disposable.dispose()
        self.presentationDataDisposable?.dispose()
        self.centralItemAttributesDisposable.dispose()
    }
    
    private func updateThemeAndStrings() {
        if self.title != nil {
            self.title = self.presentationData.strings.WallpaperPreview_Title
        }
        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBar.style.style
        self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationData: self.presentationData))
        self.toolbarNode?.updateThemeAndStrings(theme: self.presentationData.theme, strings: self.presentationData.strings)
    }
    
    func dismiss(forceAway: Bool) {
        let completion: () -> Void = { [weak self] in
            self?.presentingViewController?.dismiss(animated: false, completion: nil)
        }
        
        self.galleryNode.modalAnimateOut(completion: completion)
    }
    
    private func updateTransaction(entries: [WallpaperGalleryEntry], arguments: WallpaperGalleryItemArguments) -> GalleryPagerTransaction {
        var i: Int = 0
        var updateItems: [GalleryPagerUpdateItem] = []
        for entry in entries {
            let item = GalleryPagerUpdateItem(index: i, previousIndex: i, item: WallpaperGalleryItem(context: self.context, entry: entry, arguments: arguments))
            updateItems.append(item)
            i += 1
        }
        return GalleryPagerTransaction(deleteItems: [], insertItems: [], updateItems: updateItems, focusOnItem: self.galleryNode.pager.centralItemNode()?.index)
    }
    
    override func loadDisplayNode() {
        let controllerInteraction = GalleryControllerInteraction(presentController: { [weak self] controller, arguments in
            if let strongSelf = self {
                strongSelf.present(controller, in: .window(.root), with: arguments, blockInteraction: true)
            }
        }, dismissController: { [weak self] in
                self?.dismiss(forceAway: true)
        }, replaceRootController: { controller, ready in
        })
        self.displayNode = WallpaperGalleryControllerNode(controllerInteraction: controllerInteraction, pageGap: 0.0)
        self.displayNodeDidLoad()
        
        self.galleryNode.statusBar = self.statusBar
        self.galleryNode.navigationBar = self.navigationBar
        self.galleryNode.dismiss = { [weak self] in
            self?.presentingViewController?.dismiss(animated: false, completion: nil)
        }
        
        self.galleryNode.pager.centralItemIndexUpdated = { [weak self] index in
            if let strongSelf = self {
                strongSelf.bindCentralItemNode(animated: true)
            }
        }
        
        self.galleryNode.backgroundNode.backgroundColor = nil
        self.galleryNode.backgroundNode.isOpaque = false
        self.galleryNode.isBackgroundExtendedOverNavigationBar = true
        
        switch self.source {
            case .asset, .contextResult, .customColor:
                self.galleryNode.scrollView.isScrollEnabled = false
            default:
                break
        }
        
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let overlayNode = WallpaperGalleryOverlayNode()
        self.overlayNode = overlayNode
        self.galleryNode.overlayNode = overlayNode
        self.galleryNode.addSubnode(overlayNode)
        
        let colorPanelNode = WallpaperColorPanelNode(theme: presentationData.theme, strings: presentationData.strings)
        colorPanelNode.colorChanged = { [weak self] color, ended in
            if let strongSelf = self {
                strongSelf.updateEntries(color: color, preview: !ended)
            }
        }
        if case let .customColor(colorValue) = self.source, let color = colorValue {
            colorPanelNode.color = UIColor(rgb: UInt32(bitPattern: color))
        }
        self.colorPanelNode = colorPanelNode
        overlayNode.addSubnode(colorPanelNode)
        
        let toolbarNode = WallpaperGalleryToolbarNode(theme: presentationData.theme, strings: presentationData.strings)
        self.toolbarNode = toolbarNode
        overlayNode.addSubnode(toolbarNode)
        
        toolbarNode.cancel = { [weak self] in
            self?.dismiss(forceAway: true)
        }
        toolbarNode.done = { [weak self] in
            if let strongSelf = self {
                if let centralItemNode = strongSelf.galleryNode.pager.centralItemNode() as? WallpaperGalleryItemNode {
                    let options = centralItemNode.options
                    if !strongSelf.entries.isEmpty {
                        let entry = strongSelf.entries[centralItemNode.index]
                        switch entry {
                            case let .wallpaper(wallpaper, _):
                                var resource: MediaResource?
                                switch wallpaper {
                                    case let .file(file):
                                        resource = file.file.resource
                                    case let .image(representations, _):
                                        if let largestSize = largestImageRepresentation(representations) {
                                            resource = largestSize.resource
                                        }
                                    default:
                                        break
                                }
                                
                                let completion: (TelegramWallpaper) -> Void = { wallpaper in
                                    let baseSettings = wallpaper.settings
                                    let updatedSettings = WallpaperSettings(blur: options.contains(.blur), motion: options.contains(.motion), color: baseSettings?.color, intensity: baseSettings?.intensity)
                                    let wallpaper = wallpaper.withUpdatedSettings(updatedSettings)
                                    
                                    let _ = (updatePresentationThemeSettingsInteractively(accountManager: strongSelf.context.sharedContext.accountManager, { current in
                                        var themeSpecificChatWallpapers = current.themeSpecificChatWallpapers
                                        themeSpecificChatWallpapers[current.theme.index] = wallpaper
                                        return PresentationThemeSettings(chatWallpaper: wallpaper, theme: current.theme, themeAccentColor: current.themeAccentColor, themeSpecificChatWallpapers: themeSpecificChatWallpapers, fontSize: current.fontSize, automaticThemeSwitchSetting: current.automaticThemeSwitchSetting, disableAnimations: current.disableAnimations)
                                    }) |> deliverOnMainQueue).start(completed: {
                                        self?.dismiss(forceAway: true)
                                    })
                                
                                    switch strongSelf.source {
                                        case .wallpaper, .slug:
                                            let _ = saveWallpaper(account: strongSelf.context.account, wallpaper: wallpaper).start()
                                        default:
                                            break
                                    }
                                    let _ = installWallpaper(account: strongSelf.context.account, wallpaper: wallpaper).start()
                                }
                                
                                let applyWallpaper: (TelegramWallpaper) -> Void = { wallpaper in
                                    if options.contains(.blur) {
                                        if let resource = resource {
                                            let representation = CachedBlurredWallpaperRepresentation()
                                            let _ = strongSelf.context.account.postbox.mediaBox.cachedResourceRepresentation(resource, representation: representation, complete: true, fetch: true).start()
                                            
                                            if let path = strongSelf.context.account.postbox.mediaBox.completedResourcePath(resource), let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedRead) {
                                                strongSelf.context.sharedContext.accountManager.mediaBox.storeResourceData(resource.id, data: data)
                                                let _ = strongSelf.context.sharedContext.accountManager.mediaBox.cachedResourceRepresentation(resource, representation: representation, complete: true, fetch: true).start(completed: {
                                                    completion(wallpaper)
                                                })
                                            }
                                        }
                                    } else if case let .file(file) = wallpaper {
                                        if file.isPattern, let color = file.settings.color, let intensity = file.settings.intensity {
                                            let representation = CachedPatternWallpaperRepresentation(color: color, intensity: intensity)
                                            let _ = strongSelf.context.account.postbox.mediaBox.cachedResourceRepresentation(file.file.resource, representation: representation, complete: true, fetch: true).start()
                                            
                                            if let path = strongSelf.context.account.postbox.mediaBox.completedResourcePath(file.file.resource), let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedRead) {
                                                strongSelf.context.sharedContext.accountManager.mediaBox.storeResourceData(file.file.resource.id, data: data)
                                                let _ = strongSelf.context.sharedContext.accountManager.mediaBox.cachedResourceRepresentation(file.file.resource, representation: representation, complete: true, fetch: true).start(completed: {
                                                    completion(wallpaper)
                                                })
                                            }
                                        } else if let path = strongSelf.context.account.postbox.mediaBox.completedResourcePath(file.file.resource), let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedRead) {
                                                strongSelf.context.sharedContext.accountManager.mediaBox.storeResourceData(file.file.resource.id, data: data)
                                                completion(wallpaper)
                                        }
                                    } else {
                                        completion(wallpaper)
                                    }
                                }
                            
                                if case let .image(currentRepresentations, currentSettings) = wallpaper {
                                    let _ = (strongSelf.context.wallpaperUploadManager!.stateSignal()
                                    |> take(1)
                                    |> deliverOnMainQueue).start(next: { status in
                                        switch status {
                                            case let .uploaded(uploadedWallpaper, resultWallpaper):
                                                if case let .image(uploadedRepresentations, _) = uploadedWallpaper, uploadedRepresentations == currentRepresentations {
                                                    let updatedWallpaper = resultWallpaper.withUpdatedSettings(currentSettings)
                                                    applyWallpaper(updatedWallpaper)
                                                    return
                                                }
                                            case let .uploading(uploadedWallpaper, _):
                                                if case let .image(uploadedRepresentations, uploadedSettings) = uploadedWallpaper, uploadedRepresentations == currentRepresentations, uploadedSettings != currentSettings {
                                                    let updatedWallpaper = uploadedWallpaper.withUpdatedSettings(currentSettings)
                                                    applyWallpaper(updatedWallpaper)
                                                    return
                                                }
                                            default:
                                                break
                                        }
                                        applyWallpaper(wallpaper)
                                    })
                                } else {
                                    applyWallpaper(wallpaper)
                                }
                            default:
                                break
                        }

                        strongSelf.apply?(entry, options, centralItemNode.cropRect)
                    }
                }
            }
        }
        
        let ready = self.galleryNode.pager.ready() |> timeout(2.0, queue: Queue.mainQueue(), alternate: .single(Void())) |> afterNext { [weak self] _ in
            self?.didSetReady = true
        }
        self._ready.set(ready |> map { true })
    }
    
    private func currentEntry() -> WallpaperGalleryEntry? {
        if let centralItemNode = self.galleryNode.pager.centralItemNode() as? WallpaperGalleryItemNode {
            return centralItemNode.entry
        } else if let centralEntryIndex = self.centralEntryIndex {
            return self.entries[centralEntryIndex]
        } else {
            return nil
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        self.galleryNode.modalAnimateIn()
        self.bindCentralItemNode(animated: false)
    }
    
    private func bindCentralItemNode(animated: Bool) {
        if let node = self.galleryNode.pager.centralItemNode() as? WallpaperGalleryItemNode {
            self.centralItemSubtitle.set(node.subtitle.get())
            self.centralItemStatus.set(node.status.get())
            self.centralItemAction.set(node.actionButton.get())
            node.action = { [weak self] in
                self?.actionPressed()
            }
            node.requestPatternPanel = { [weak self] enabled in
                if let strongSelf = self, let (layout, _) = strongSelf.validLayout {
                    strongSelf.patternPanelEnabled = enabled
                    strongSelf.galleryNode.scrollView.isScrollEnabled = !enabled
                    if enabled {
                        strongSelf.patternPanelNode?.didAppear()
                    } else {
                        strongSelf.updateEntries(pattern: .color(0), preview: false)
                    }
                    strongSelf.containerLayoutUpdated(layout, transition: .animated(duration: 0.3, curve: .spring))
                }
            }
            
            if let (layout, bottomInset) = self.validLayout {
                self.updateMessagesLayout(layout: layout, bottomInset: bottomInset, transition: .immediate)
            }
        }
    }
    
    private func updateEntries(color: UIColor, preview: Bool = false) {
        guard self.validLayout != nil, let centralEntryIndex = self.galleryNode.pager.centralItemNode()?.index else {
            return
        }
        
        var entries = self.entries
        var currentEntry = entries[centralEntryIndex]
        switch currentEntry {
            case let .wallpaper(wallpaper, _):
                switch wallpaper {
                    case .color:
                        currentEntry = .wallpaper(.color(Int32(color.rgb)), nil)
                    default:
                        break
                }
            default:
                break
        }
        entries[centralEntryIndex] = currentEntry
        self.entries = entries
        
        self.galleryNode.pager.transaction(self.updateTransaction(entries: entries, arguments: WallpaperGalleryItemArguments(colorPreview: preview, isColorsList: false, patternEnabled: self.patternPanelEnabled)))
    }
    
    private func updateEntries(pattern: TelegramWallpaper?, intensity: Int32? = nil, preview: Bool = false) {
        var updatedEntries: [WallpaperGalleryEntry] = []
        for entry in self.entries {
            var entryColor: Int32?
            if case let .wallpaper(wallpaper, _) = entry {
                if case let .color(color) = wallpaper {
                    entryColor = color
                } else if case let .file(file) = wallpaper {
                    entryColor = file.settings.color
                }
            }
            
            if let entryColor = entryColor {
                if let pattern = pattern, case let .file(file) = pattern {
                    let newSettings = WallpaperSettings(blur: file.settings.blur, motion: file.settings.motion, color: entryColor, intensity: intensity)
                    let newWallpaper = TelegramWallpaper.file(id: file.id, accessHash: file.accessHash, isCreator: file.isCreator, isDefault: file.isDefault, isPattern: file.isPattern, isDark: file.isDark, slug: file.slug, file: file.file, settings: newSettings)
                    updatedEntries.append(.wallpaper(newWallpaper, nil))
                } else {
                    let newWallpaper = TelegramWallpaper.color(entryColor)
                    updatedEntries.append(.wallpaper(newWallpaper, nil))
                }
            }
        }
        
        self.entries = updatedEntries
        self.galleryNode.pager.transaction(self.updateTransaction(entries: updatedEntries, arguments: WallpaperGalleryItemArguments(colorPreview: preview, isColorsList: true, patternEnabled: self.patternPanelEnabled)))
    }
    
    private func updateMessagesLayout(layout: ContainerViewLayout, bottomInset: CGFloat, transition: ContainedViewLayoutTransition) {
        var items: [ChatMessageItem] = []
        let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: 1)
        let otherPeerId = self.context.account.peerId
        var peers = SimpleDictionary<PeerId, Peer>()
        let messages = SimpleDictionary<MessageId, Message>()
        peers[peerId] = TelegramUser(id: peerId, accessHash: nil, firstName: self.presentationData.strings.Appearance_PreviewReplyAuthor, lastName: "", username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [])
        peers[otherPeerId] = TelegramUser(id: otherPeerId, accessHash: nil, firstName: self.presentationData.strings.Appearance_PreviewReplyAuthor, lastName: "", username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [])
        
        var currentWallpaper: TelegramWallpaper = self.presentationData.chatWallpaper
        if let entry = self.currentEntry(), case let .wallpaper(wallpaper, _) = entry {
            currentWallpaper = wallpaper
        }
        
        let controllerInteraction = ChatControllerInteraction.default
        let chatPresentationData = ChatPresentationData(theme: ChatPresentationThemeData(theme: self.presentationData.theme, wallpaper: currentWallpaper), fontSize: self.presentationData.fontSize, strings: self.presentationData.strings, dateTimeFormat: self.presentationData.dateTimeFormat, nameDisplayOrder: self.presentationData.nameDisplayOrder, disableAnimations: false)
        
        var topMessageText: String
        var bottomMessageText: String
        switch self.source {
            case .wallpaper, .slug:
                topMessageText = presentationData.strings.WallpaperPreview_PreviewTopText
                bottomMessageText = presentationData.strings.WallpaperPreview_PreviewBottomText
            case let .list(_, _, type):
                switch type {
                    case .wallpapers:
                        topMessageText = presentationData.strings.WallpaperPreview_SwipeTopText
                        bottomMessageText = presentationData.strings.WallpaperPreview_SwipeBottomText
                    case .colors:
                        topMessageText = presentationData.strings.WallpaperPreview_SwipeColorsTopText
                        bottomMessageText = presentationData.strings.WallpaperPreview_SwipeColorsBottomText
                }
            case .asset, .contextResult:
                topMessageText = presentationData.strings.WallpaperPreview_CropTopText
                bottomMessageText = presentationData.strings.WallpaperPreview_CropBottomText
            case .customColor:
                topMessageText = presentationData.strings.WallpaperPreview_CustomColorTopText
                bottomMessageText = presentationData.strings.WallpaperPreview_CustomColorBottomText
        }
        
        if self.colorPanelEnabled {
            topMessageText = presentationData.strings.WallpaperPreview_CustomColorTopText
            bottomMessageText = presentationData.strings.WallpaperPreview_CustomColorBottomText
        }
        
        items.append(ChatMessageItem(presentationData: chatPresentationData, context: self.context, chatLocation: .peer(peerId), associatedData: ChatMessageItemAssociatedData(automaticDownloadPeerType: .contact, automaticDownloadNetworkType: .cellular, isRecentActions: false), controllerInteraction: controllerInteraction, content: .message(message: Message(stableId: 2, stableVersion: 0, id: MessageId(peerId: peerId, namespace: 0, id: 2), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, timestamp: 66001, flags: [], tags: [], globalTags: [], localTags: [], forwardInfo: nil, author: peers[otherPeerId], text: bottomMessageText, attributes: [], media: [], peers: peers, associatedMessages: messages, associatedMessageIds: []), read: true, selection: .none, attributes: ChatMessageEntryAttributes(isAdmin: false, isContact: false)), disableDate: false))
        
        items.append(ChatMessageItem(presentationData: chatPresentationData, context: self.context, chatLocation: .peer(peerId), associatedData: ChatMessageItemAssociatedData(automaticDownloadPeerType: .contact, automaticDownloadNetworkType: .cellular, isRecentActions: false), controllerInteraction: controllerInteraction, content: .message(message: Message(stableId: 1, stableVersion: 0, id: MessageId(peerId: peerId, namespace: 0, id: 1), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, timestamp: 66000, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, author: peers[peerId], text: topMessageText, attributes: [], media: [], peers: peers, associatedMessages: messages, associatedMessageIds: []), read: true, selection: .none, attributes: ChatMessageEntryAttributes(isAdmin: false, isContact: false)), disableDate: false))
        
        let params = ListViewItemLayoutParams(width: layout.size.width, leftInset: layout.safeInsets.left, rightInset: layout.safeInsets.right)
        if let messageNodes = self.messageNodes {
            for i in 0 ..< items.count {
                let itemNode = messageNodes[i]
                items[i].updateNode(async: { $0() }, node: {
                    return itemNode
                }, params: params, previousItem: i == 0 ? nil : items[i - 1], nextItem: i == (items.count - 1) ? nil : items[i + 1], animation: .None, completion: { (layout, apply) in
                    let nodeFrame = CGRect(origin: itemNode.frame.origin, size: CGSize(width: layout.size.width, height: layout.size.height))
                    
                    itemNode.contentSize = layout.contentSize
                    itemNode.insets = layout.insets
                    itemNode.frame = nodeFrame
                    itemNode.isUserInteractionEnabled = false
                    
                    apply(ListViewItemApply(isOnScreen: true))
                })
            }
        } else {
            var messageNodes: [ListViewItemNode] = []
            for i in 0 ..< items.count {
                var itemNode: ListViewItemNode?
                items[i].nodeConfiguredForParams(async: { $0() }, params: params, synchronousLoads: false, previousItem: i == 0 ? nil : items[i - 1], nextItem: i == (items.count - 1) ? nil : items[i + 1], completion: { node, apply in
                    itemNode = node
                    apply().1(ListViewItemApply(isOnScreen: true))
                })
                itemNode!.subnodeTransform = CATransform3DMakeRotation(CGFloat.pi, 0.0, 0.0, 1.0)
                itemNode!.isUserInteractionEnabled = false
                messageNodes.append(itemNode!)
                self.overlayNode?.addSubnode(itemNode!)
            }
            self.messageNodes = messageNodes
        }
        
        if let messageNodes = self.messageNodes {
            var bottomOffset: CGFloat = layout.size.height - bottomInset - 9.0
            if self.colorPanelEnabled {
            } else {
                bottomOffset -= 66.0
            }
            for itemNode in messageNodes {
                transition.updateFrame(node: itemNode, frame: CGRect(origin: CGPoint(x: 0.0, y: bottomOffset - itemNode.frame.height), size: itemNode.frame.size))
                bottomOffset -= itemNode.frame.height
            }
        }
    }
    
    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        let hadLayout = self.validLayout != nil
        
        super.containerLayoutUpdated(layout, transition: transition)
        
        self.galleryNode.frame = CGRect(origin: CGPoint(), size: layout.size)
        self.galleryNode.containerLayoutUpdated(layout, navigationBarHeight: self.navigationHeight, transition: transition)
        self.overlayNode?.frame = self.galleryNode.bounds
        
        transition.updateFrame(node: self.toolbarNode!, frame: CGRect(origin: CGPoint(x: 0.0, y: layout.size.height - 49.0 - layout.intrinsicInsets.bottom), size: CGSize(width: layout.size.width, height: 49.0 + layout.intrinsicInsets.bottom)))
        self.toolbarNode!.updateLayout(size: CGSize(width: layout.size.width, height: 49.0), layout: layout, transition: transition)
        
        var bottomInset = layout.intrinsicInsets.bottom + 49.0
        let metrics = DeviceMetrics.forScreenSize(layout.size)
        let standardInputHeight = metrics?.standardInputHeight(inLandscape: false) ?? 216.0
        let height = standardInputHeight - bottomInset + 47.0
        
        if let colorPanelNode = self.colorPanelNode {
            var colorPanelFrame = CGRect(x: 0.0, y: layout.size.height, width: layout.size.width, height: height)
            if self.colorPanelEnabled {
                colorPanelFrame.origin = CGPoint(x: 0.0, y: layout.size.height - bottomInset - height)
                bottomInset += height
            }
            
            transition.updateFrame(node: colorPanelNode, frame: colorPanelFrame)
            colorPanelNode.updateLayout(size: colorPanelFrame.size, keyboardHeight: layout.inputHeight ?? 0.0, transition: transition)
        }
        
        let currentPatternPanelNode: WallpaperPatternPanelNode
        if let patternPanelNode = self.patternPanelNode {
            currentPatternPanelNode = patternPanelNode
        } else {
            let patternPanelNode = WallpaperPatternPanelNode(context: self.context, theme: presentationData.theme, strings: presentationData.strings)
            patternPanelNode.patternChanged = { [weak self] pattern, intensity, preview in
                if let strongSelf = self, strongSelf.validLayout != nil {
                    strongSelf.updateEntries(pattern: pattern, intensity: intensity, preview: preview)
                }
            }
            self.patternPanelNode = patternPanelNode
            currentPatternPanelNode = patternPanelNode
            self.overlayNode?.insertSubnode(patternPanelNode, belowSubnode: self.toolbarNode!)
        }
        
        let panelHeight: CGFloat = 190.0
        var patternPanelFrame = CGRect(x: 0.0, y: layout.size.height, width: layout.size.width, height: panelHeight)
        if self.patternPanelEnabled {
            patternPanelFrame.origin = CGPoint(x: 0.0, y: layout.size.height - bottomInset - panelHeight)
            bottomInset += panelHeight
        }
        
        transition.updateFrame(node: currentPatternPanelNode, frame: patternPanelFrame)
        currentPatternPanelNode.updateLayout(size: patternPanelFrame.size, transition: transition)
        
        self.updateMessagesLayout(layout: layout, bottomInset: bottomInset, transition: transition)

        self.validLayout = (layout, bottomInset)
        if !hadLayout {
            var colors = false
            if case let .list(_, _, type) = self.source, case .colors = type {
                colors = true
            }
            
            self.galleryNode.pager.replaceItems(self.entries.map({ WallpaperGalleryItem(context: self.context, entry: $0, arguments: WallpaperGalleryItemArguments(isColorsList: colors)) }), centralItemIndex: self.centralEntryIndex)
            
            if let initialOptions = self.initialOptions, let itemNode = self.galleryNode.pager.centralItemNode() as? WallpaperGalleryItemNode {
                itemNode.options = initialOptions
            }
        }
    }
    
    private func actionPressed() {
        guard let entry = self.currentEntry(), case let .wallpaper(wallpaper, _) = entry, let itemNode = self.galleryNode.pager.centralItemNode() as? WallpaperGalleryItemNode else {
            return
        }
        
        var controller: ShareController?
        var options: [String] = []
        if (itemNode.options.contains(.blur)) {
            if (itemNode.options.contains(.motion)) {
                options.append("mode=blur+motion")
            } else {
                options.append("mode=blur")
            }
        } else if (itemNode.options.contains(.motion)) {
            options.append("mode=motion")
        }
        
        let context = self.context
        switch wallpaper {
            case .image:
                let _ = (context.wallpaperUploadManager!.stateSignal()
                |> take(1)
                |> filter { status -> Bool in
                    return status.wallpaper == wallpaper
                }).start(next: { [weak self] status in
                    if case let .uploaded(uploadedWallpaper, resultWallpaper) = status, uploadedWallpaper == wallpaper, case let .file(file) = resultWallpaper {
                        var optionsString = ""
                        if !options.isEmpty {
                            optionsString = "?\(options.joined(separator: "&"))"
                        }
                        
                        let controller = ShareController(context: context, subject: .url("https://t.me/bg/\(file.slug)\(optionsString)"))
                        self?.present(controller, in: .window(.root), blockInteraction: true)
                    }
                })
            case let .file(_, _, _, _, isPattern, _, slug, _, settings):
                if isPattern {
                    if let color = settings.color {
                        options.append("bg_color=\(UIColor(rgb: UInt32(bitPattern: color)).hexString)")
                    }
                    if let intensity = settings.intensity {
                        options.append("intensity=\(intensity)")
                    }
                }
                
                var optionsString = ""
                if !options.isEmpty {
                    optionsString = "?\(options.joined(separator: "&"))"
                }
                
                controller = ShareController(context: context, subject: .url("https://t.me/bg/\(slug)\(optionsString)"))
            case let .color(color):
                controller = ShareController(context: context, subject: .url("https://t.me/bg/\(UIColor(rgb: UInt32(bitPattern: color)).hexString)"))
            default:
                break
        }
        if let controller = controller {
            self.present(controller, in: .window(.root), blockInteraction: true)
        }
    }
}

private extension GalleryControllerNode {
    func modalAnimateIn(completion: (() -> Void)? = nil) {
        self.layer.animatePosition(from: CGPoint(x: self.layer.position.x, y: self.layer.position.y + self.layer.bounds.size.height), to: self.layer.position, duration: 0.5, timingFunction: kCAMediaTimingFunctionSpring)
    }
    
    func modalAnimateOut(completion: (() -> Void)? = nil) {
        self.layer.animatePosition(from: self.layer.position, to: CGPoint(x: self.layer.position.x, y: self.layer.position.y + self.layer.bounds.size.height), duration: 0.2, timingFunction: kCAMediaTimingFunctionEaseInEaseOut, removeOnCompletion: false, completion: { _ in
            completion?()
        })
    }
}
