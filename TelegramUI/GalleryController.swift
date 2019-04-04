import Foundation
import Display
import QuickLook
import Postbox
import SwiftSignalKit
import AsyncDisplayKit
import TelegramCore
import SafariServices

private func tagsForMessage(_ message: Message) -> MessageTags? {
    for media in message.media {
        switch media {
            case _ as TelegramMediaImage:
                return .photoOrVideo
            case let file as TelegramMediaFile:
                if file.isVideo {
                    if !file.isAnimated {
                        return .photoOrVideo
                    }
                } else if file.isVoice {
                    return .voiceOrInstantVideo
                } else if file.isSticker {
                    return nil
                } else {
                    return .file
                }
            default:
                break
        }
    }
    return nil
}

private func galleryMediaForMedia(media: Media) -> Media? {
    if let media = media as? TelegramMediaImage {
        return media
    } else if let file = media as? TelegramMediaFile {
        if file.mimeType.hasPrefix("audio/") {
            return nil
        } else if !file.isVideo && file.mimeType.hasPrefix("video/") {
            return file
        } else {
            return file
        }
    }
    return nil
}

private func mediaForMessage(message: Message) -> (Media, TelegramMediaImage?)? {
    for media in message.media {
        if let result = galleryMediaForMedia(media: media) {
            return (result, nil)
        } else if let webpage = media as? TelegramMediaWebpage {
            switch webpage.content {
                case let .Loaded(content):
                    if let embedUrl = content.embedUrl, !embedUrl.isEmpty {
                        return (webpage, nil)
                    } else if let file = content.file {
                        if let result = galleryMediaForMedia(media: file) {
                            return (result, content.image)
                        }
                    } else if let image = content.image {
                        if let result = galleryMediaForMedia(media: image) {
                            return (result, nil)
                        }
                    }
                case .Pending:
                    break
            }
        }
    }
    return nil
}

private let internalExtensions = Set<String>([
    "jpg",
    "png",
    "jpeg"
])

private let internalNotSupportedExtensions = Set<String>([
    "djvu"
])

private let internalMimeTypes = Set<String>([
])

private let internalMimePrefixes: [String] = [
    "image/jpeg",
    "image/jpg",
    "image/png"
]

func internalDocumentItemSupportsMimeType(_ type: String, fileName: String?) -> Bool {
    if let fileName = fileName {
        let ext = (fileName as NSString).pathExtension
        if internalExtensions.contains(ext.lowercased()) {
            return true
        }
        if internalNotSupportedExtensions.contains(ext.lowercased()) {
            return false
        }
    }
    
    if internalMimeTypes.contains(type) {
        return true
    }
    for prefix in internalMimePrefixes {
        if type.hasPrefix(prefix) {
            return true
        }
    }
    return false
}

private let textFont = Font.regular(16.0)
private let boldFont = Font.bold(16.0)
private let italicFont = Font.italic(16.0)
private let fixedFont = UIFont(name: "Menlo-Regular", size: 15.0) ?? textFont

func galleryCaptionStringWithAppliedEntities(_ text: String, entities: [MessageTextEntity]) -> NSAttributedString {
    return stringWithAppliedEntities(text, entities: entities, baseColor: .white, linkColor: UIColor(rgb: 0x5ac8fa), baseFont: textFont, linkFont: textFont, boldFont: boldFont, italicFont: italicFont, fixedFont: fixedFont, underlineLinks: false)
}

private func galleryMessageCaptionText(_ message: Message) -> String {
    for media in message.media {
        if let _ = media as? TelegramMediaWebpage {
            return ""
        }
    }
    return message.text
}

func galleryItemForEntry(context: AccountContext, presentationData: PresentationData, entry: MessageHistoryEntry, isCentral: Bool = false, streamVideos: Bool, loopVideos: Bool = false, hideControls: Bool = false, fromPlayingVideo: Bool = false, landscape: Bool = false, tempFilePath: String? = nil, playbackCompleted: @escaping () -> Void = {}, performAction: @escaping (GalleryControllerInteractionTapAction) -> Void = { _ in }, openActionOptions: @escaping (GalleryControllerInteractionTapAction) -> Void = { _ in }) -> GalleryItem? {
    switch entry {
        case let .MessageEntry(message, _, location, _, _):
            if let (media, mediaImage) = mediaForMessage(message: message) {
                if let _ = media as? TelegramMediaImage {
                    return ChatImageGalleryItem(context: context, presentationData: presentationData, message: message, location: location, performAction: performAction, openActionOptions: openActionOptions)
                } else if let file = media as? TelegramMediaFile {
                    if file.isVideo {
                        let content: UniversalVideoContent
                        if file.isAnimated {
                            content = NativeVideoContent(id: .message(message.id, message.stableId, file.fileId), fileReference: .message(message: MessageReference(message), media: file), imageReference: mediaImage.flatMap({ ImageMediaReference.message(message: MessageReference(message), media: $0) }), loopVideo: true, enableSound: false, tempFilePath: tempFilePath)
                        } else {
                            if true || (file.mimeType == "video/mpeg4" || file.mimeType == "video/mov" || file.mimeType == "video/mp4") {
                                content = NativeVideoContent(id: .message(message.id, message.stableId, file.fileId), fileReference: .message(message: MessageReference(message), media: file), imageReference: mediaImage.flatMap({ ImageMediaReference.message(message: MessageReference(message), media: $0) }), streamVideo: .conservative, loopVideo: loopVideos, tempFilePath: tempFilePath)
                            } else {
                                content = PlatformVideoContent(id: .message(message.id, message.stableId, file.fileId), fileReference: .message(message: MessageReference(message), media: file), streamVideo: streamVideos, loopVideo: loopVideos)
                            }
                        }
                        
                        var entities: [MessageTextEntity] = []
                        for attribute in message.attributes {
                            if let attribute = attribute as? TextEntitiesMessageAttribute {
                                entities = attribute.entities
                                break
                            }
                        }
                        let caption = galleryCaptionStringWithAppliedEntities(galleryMessageCaptionText(message), entities: entities)
                        return UniversalVideoGalleryItem(context: context, presentationData: presentationData, content: content, originData: GalleryItemOriginData(title: message.author?.displayTitle, timestamp: message.timestamp), indexData: location.flatMap { GalleryItemIndexData(position: Int32($0.index), totalCount: Int32($0.count)) }, contentInfo: .message(message), caption: caption, hideControls: hideControls, fromPlayingVideo: fromPlayingVideo, landscape: landscape, playbackCompleted: playbackCompleted, performAction: performAction, openActionOptions: openActionOptions)
                    } else {
                        if file.mimeType.hasPrefix("image/") && file.mimeType != "image/gif" {
                            var pixelsCount: Int = 0
                            if let dimensions = file.dimensions {
                                pixelsCount = Int(dimensions.width) * Int(dimensions.height)
                            }
                            if (file.size == nil || file.size! < 4 * 1024 * 1024) && pixelsCount < 4096 * 4096 {
                                return ChatImageGalleryItem(context: context, presentationData: presentationData, message: message, location: location, performAction: performAction, openActionOptions: openActionOptions)
                            } else {
                                return ChatDocumentGalleryItem(context: context, presentationData: presentationData, message: message, location: location)
                            }
                        } else if internalDocumentItemSupportsMimeType(file.mimeType, fileName: file.fileName) {
                            return ChatDocumentGalleryItem(context: context, presentationData: presentationData, message: message, location: location)
                        } else {
                            return ChatExternalFileGalleryItem(context: context, presentationData: presentationData, message: message, location: location)
                        }
                    }
                } else if let webpage = media as? TelegramMediaWebpage, case let .Loaded(webpageContent) = webpage.content {
                    var content: UniversalVideoContent?
                    switch websiteType(of: webpageContent) {
                        case .instagram where webpageContent.file != nil && webpageContent.image != nil && webpageContent.file!.isVideo:
                            content = NativeVideoContent(id: .message(message.id, message.stableId, webpageContent.file?.id ?? webpage.webpageId), fileReference: .message(message: MessageReference(message), media: webpageContent.file!), imageReference: webpageContent.image.flatMap({ ImageMediaReference.message(message: MessageReference(message), media: $0) }), streamVideo: .conservative, enableSound: true)
                        default:
                            if let embedUrl = webpageContent.embedUrl, let image = webpageContent.image {
                                if let file = webpageContent.file, file.isVideo {
                                    content = NativeVideoContent(id: .message(message.id, message.stableId, file.fileId), fileReference: .message(message: MessageReference(message), media: file), imageReference: mediaImage.flatMap({ ImageMediaReference.message(message: MessageReference(message), media: $0) }), streamVideo: .conservative, loopVideo: loopVideos, tempFilePath: tempFilePath)
                                } else if URL(string: embedUrl)?.pathExtension == "mp4" {
                                    content = SystemVideoContent(url: embedUrl, imageReference: .webPage(webPage: WebpageReference(webpage), media: image), dimensions: webpageContent.embedSize ?? CGSize(width: 640.0, height: 640.0), duration: Int32(webpageContent.duration ?? 0))
                                }
                            }
                            if content == nil, let webEmbedContent = WebEmbedVideoContent(webPage: webpage, webpageContent: webpageContent) {
                                content = webEmbedContent
                            }
                    }
                    if let content = content {
                        return UniversalVideoGalleryItem(context: context, presentationData: presentationData, content: content, originData: GalleryItemOriginData(title: message.author?.displayTitle, timestamp: message.timestamp), indexData: location.flatMap { GalleryItemIndexData(position: Int32($0.index), totalCount: Int32($0.count)) }, contentInfo: .message(message), caption: NSAttributedString(string: ""), fromPlayingVideo: fromPlayingVideo, landscape: landscape, performAction: performAction, openActionOptions: openActionOptions)
                    } else {
                        return nil
                    }
                }
            }
        default:
            break
    }
    return nil
}

final class GalleryTransitionArguments {
    let transitionNode: (ASDisplayNode, () -> (UIView?, UIView?))
    let addToTransitionSurface: (UIView) -> Void
    
    init(transitionNode: (ASDisplayNode, () -> (UIView?, UIView?)), addToTransitionSurface: @escaping (UIView) -> Void) {
        self.transitionNode = transitionNode
        self.addToTransitionSurface = addToTransitionSurface
    }
}

final class GalleryControllerPresentationArguments {
    let animated: Bool
    let transitionArguments: (MessageId, Media) -> GalleryTransitionArguments?
    
    init(animated: Bool = true, transitionArguments: @escaping (MessageId, Media) -> GalleryTransitionArguments?) {
        self.animated = animated
        self.transitionArguments = transitionArguments
    }
}

private enum GalleryMessageHistoryView {
    case view(MessageHistoryView)
    case single(MessageHistoryEntry)
    
    var entries: [MessageHistoryEntry] {
        switch self {
            case let .view(view):
                return view.entries
            case let .single(entry):
                return [entry]
        }
    }
}

enum GalleryControllerItemSource {
    case peerMessagesAtId(MessageId)
    case standaloneMessage(Message)
}

enum GalleryControllerInteractionTapAction {
    case url(url: String, concealed: Bool)
    case textMention(String)
    case peerMention(PeerId, String)
    case botCommand(String)
    case hashtag(String?, String)
}

final class GalleryControllerActionInteraction {
    let openUrl: (String, Bool) -> Void
    let openUrlIn: (String) -> Void
    let openPeerMention: (String) -> Void
    let openPeer: (PeerId) -> Void
    let openHashtag: (String?, String) -> Void
    let openBotCommand: (String) -> Void
    let addContact: (String) -> Void

    init(openUrl: @escaping (String, Bool) -> Void, openUrlIn: @escaping (String) -> Void, openPeerMention: @escaping (String) -> Void, openPeer: @escaping (PeerId) -> Void, openHashtag: @escaping (String?, String) -> Void, openBotCommand: @escaping (String) -> Void, addContact: @escaping (String) -> Void) {
        self.openUrl = openUrl
        self.openUrlIn = openUrlIn
        self.openPeerMention = openPeerMention
        self.openPeer = openPeer
        self.openHashtag = openHashtag
        self.openBotCommand = openBotCommand
        self.addContact = addContact
    }
}

class GalleryController: ViewController {
    static let darkNavigationTheme = NavigationBarTheme(buttonColor: .white, disabledButtonColor: UIColor(rgb: 0x525252), primaryTextColor: .white, backgroundColor: UIColor(white: 0.0, alpha: 0.6), separatorColor: UIColor(white: 0.0, alpha: 0.8), badgeBackgroundColor: .clear, badgeStrokeColor: .clear, badgeTextColor: .clear)
    static let lightNavigationTheme = NavigationBarTheme(buttonColor: UIColor(rgb: 0x007ee5), disabledButtonColor: UIColor(rgb: 0xd0d0d0), primaryTextColor: .black, backgroundColor: UIColor(red: 0.968626451, green: 0.968626451, blue: 0.968626451, alpha: 1.0), separatorColor: UIColor(red: 0.6953125, green: 0.6953125, blue: 0.6953125, alpha: 1.0), badgeBackgroundColor: .clear, badgeStrokeColor: .clear, badgeTextColor: .clear)
    
    private var galleryNode: GalleryControllerNode {
        return self.displayNode as! GalleryControllerNode
    }
    
    private let context: AccountContext
    private var presentationData: PresentationData
    private let source: GalleryControllerItemSource
    
    private let streamVideos: Bool
    
    private let _ready = Promise<Bool>()
    override var ready: Promise<Bool> {
        return self._ready
    }
    private var didSetReady = false
    
    private var adjustedForInitialPreviewingLayout = false
    
    var temporaryDoNotWaitForReady = false
    private let fromPlayingVideo: Bool
    private let landscape: Bool
    
    private let accountInUseDisposable = MetaDisposable()
    private let disposable = MetaDisposable()
    
    private var entries: [MessageHistoryEntry] = []
    private var centralEntryStableId: UInt32?
    
    private let centralItemTitle = Promise<String>()
    private let centralItemTitleView = Promise<UIView?>()
    private let centralItemRightBarButtonItem = Promise<UIBarButtonItem?>()
    private let centralItemNavigationStyle = Promise<GalleryItemNodeNavigationStyle>()
    private let centralItemFooterContentNode = Promise<GalleryFooterContentNode?>()
    private let centralItemAttributesDisposable = DisposableSet();
    
    private let _hiddenMedia = Promise<(MessageId, Media)?>(nil)
    
    private let replaceRootController: (ViewController, ValuePromise<Bool>?) -> Void
    private let baseNavigationController: NavigationController?
    
    private var hiddenMediaManagerIndex: Int?
    
    private let actionInteraction: GalleryControllerActionInteraction?
    private var performAction: (GalleryControllerInteractionTapAction) -> Void
    private var openActionOptions: (GalleryControllerInteractionTapAction) -> Void
    
    init(context: AccountContext, source: GalleryControllerItemSource, invertItemOrder: Bool = false, streamSingleVideo: Bool = false, fromPlayingVideo: Bool = false, landscape: Bool = false, synchronousLoad: Bool = false, replaceRootController: @escaping (ViewController, ValuePromise<Bool>?) -> Void, baseNavigationController: NavigationController?, actionInteraction: GalleryControllerActionInteraction? = nil) {
        self.context = context
        self.source = source
        self.replaceRootController = replaceRootController
        self.baseNavigationController = baseNavigationController
        self.actionInteraction = actionInteraction
        self.streamVideos = streamSingleVideo
        self.fromPlayingVideo = fromPlayingVideo
        self.landscape = landscape
        
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        
        var performActionImpl: ((GalleryControllerInteractionTapAction) -> Void)?
        self.performAction = { action in
            performActionImpl?(action)
        }
        
        var openActionOptionsImpl: ((GalleryControllerInteractionTapAction) -> Void)?
        self.openActionOptions = { action in
            openActionOptionsImpl?(action)
        }
        
        super.init(navigationBarPresentationData: NavigationBarPresentationData(theme: GalleryController.darkNavigationTheme, strings: NavigationBarStrings(presentationStrings: self.presentationData.strings)))
        
        let backItem = UIBarButtonItem(backButtonAppearanceWithTitle: presentationData.strings.Common_Back, target: self, action: #selector(self.donePressed))
        self.navigationItem.leftBarButtonItem = backItem
        
        self.statusBar.statusBarStyle = .White
        
        let message: Signal<Message?, NoError>
        switch source {
            case let .peerMessagesAtId(messageId):
                message = context.account.postbox.messageAtId(messageId)
            case let .standaloneMessage(m):
                message = .single(m)
        }
        
        let messageView = message
        |> filter({ $0 != nil })
        |> mapToSignal { message -> Signal<GalleryMessageHistoryView?, NoError> in
            switch source {
                case .peerMessagesAtId:
                    if let tags = tagsForMessage(message!) {
                        let view = context.account.postbox.aroundMessageHistoryViewForLocation(.peer(message!.id.peerId), index: .message(MessageIndex(message!)), anchorIndex: .message(MessageIndex(message!)), count: 50, clipHoles: false, fixedCombinedReadStates: nil, topTaggedMessageIdNamespaces: [], tagMask: tags, orderStatistics: [.combinedLocation])
                        
                        return view
                        |> mapToSignal { (view, _, _) -> Signal<GalleryMessageHistoryView?, NoError> in
                            let mapped = GalleryMessageHistoryView.view(view)
                            return .single(mapped)
                        }
                    } else {
                        return .single(GalleryMessageHistoryView.single(MessageHistoryEntry.MessageEntry(message!, false, nil, nil, MutableMessageHistoryEntryAttributes(authorIsContact: false))))
                    }
                case .standaloneMessage:
                    return .single(GalleryMessageHistoryView.single(MessageHistoryEntry.MessageEntry(message!, false, nil, nil, MutableMessageHistoryEntryAttributes(authorIsContact: false))))
            }
        }
        |> take(1)
        
        let semaphore: DispatchSemaphore?
        if synchronousLoad {
            semaphore = DispatchSemaphore(value: 0)
        } else {
            semaphore = nil
        }
        
        let syncResult = Atomic<(Bool, (() -> Void)?)>(value: (false, nil))
        self.disposable.set(messageView.start(next: { [weak self] view in
            let f: () -> Void = {
                if let strongSelf = self {
                    if let view = view {
                        let entries = view.entries.filter { entry in
                            if case .MessageEntry = entry {
                                return true
                            } else {
                                return false
                            }
                        }
                        var centralEntryStableId: UInt32?
                        loop: for i in 0 ..< entries.count {
                            switch entries[i] {
                                case let .MessageEntry(message, _, _, _, _):
                                    switch source {
                                        case let .peerMessagesAtId(messageId):
                                            if message.id == messageId {
                                                centralEntryStableId = message.stableId
                                                break loop
                                            }
                                        case let .standaloneMessage(m):
                                            if message.id == m.id {
                                                centralEntryStableId = message.stableId
                                                break loop
                                            }
                                    }
                                default:
                                    break
                            }
                        }
                        if invertItemOrder {
                            strongSelf.entries = entries.reversed()
                            if let centralEntryStableId = centralEntryStableId {
                                strongSelf.centralEntryStableId = centralEntryStableId
                            }
                        } else {
                            strongSelf.entries = entries
                            strongSelf.centralEntryStableId = centralEntryStableId
                        }
                        if strongSelf.isViewLoaded {
                            var items: [GalleryItem] = []
                            var centralItemIndex: Int?
                            for entry in strongSelf.entries {
                                var isCentral = false
                                if case let .MessageEntry(message, _, _, _, _) = entry, message.stableId == strongSelf.centralEntryStableId {
                                    isCentral = true
                                }
                                if let item = galleryItemForEntry(context: context, presentationData: strongSelf.presentationData, entry: entry, isCentral: isCentral, streamVideos: streamSingleVideo, fromPlayingVideo: isCentral && fromPlayingVideo, landscape: isCentral && landscape, performAction: strongSelf.performAction, openActionOptions: strongSelf.openActionOptions) {
                                    if isCentral {
                                        centralItemIndex = items.count
                                    }
                                    items.append(item)
                                }
                            }
                            
                            strongSelf.galleryNode.pager.replaceItems(items, centralItemIndex: centralItemIndex)
                            
                            if strongSelf.temporaryDoNotWaitForReady {
                                strongSelf.didSetReady = true
                                strongSelf._ready.set(.single(true))
                            } else {
                                let ready = strongSelf.galleryNode.pager.ready() |> timeout(2.0, queue: Queue.mainQueue(), alternate: .single(Void())) |> afterNext { [weak strongSelf] _ in
                                    strongSelf?.didSetReady = true
                                }
                                strongSelf._ready.set(ready |> map { true })
                            }
                        }
                    }
                }
            }
            var process = false
            let _ = syncResult.modify { processed, _ in
                if !processed {
                    return (processed, f)
                }
                process = true
                return (true, nil)
            }
            semaphore?.signal()
            if process {
                Queue.mainQueue().async {
                    f()
                }
            }
        }))
        
        if let semaphore = semaphore {
            let _ = semaphore.wait(timeout: DispatchTime.now() + 1.0)
        }
        
        var syncResultApply: (() -> Void)?
        let _ = syncResult.modify { processed, f in
            syncResultApply = f
            return (true, nil)
        }
        
        syncResultApply?()
        
        self.centralItemAttributesDisposable.add(self.centralItemTitle.get().start(next: { [weak self] title in
            self?.navigationItem.title = title
        }))
        
        self.centralItemAttributesDisposable.add(self.centralItemTitleView.get().start(next: { [weak self] titleView in
            self?.navigationItem.titleView = titleView
        }))
        
        self.centralItemAttributesDisposable.add(self.centralItemRightBarButtonItem.get().start(next: { [weak self] rightBarButtonItem in
            self?.navigationItem.rightBarButtonItem = rightBarButtonItem
        }))
        
        self.centralItemAttributesDisposable.add(self.centralItemFooterContentNode.get().start(next: { [weak self] footerContentNode in
            self?.galleryNode.updatePresentationState({
                $0.withUpdatedFooterContentNode(footerContentNode)
            }, transition: .immediate)
        }))
        
        self.centralItemAttributesDisposable.add(self.centralItemNavigationStyle.get().start(next: { [weak self] style in
            if let strongSelf = self {
                switch style {
                    case .dark:
                        strongSelf.statusBar.statusBarStyle = .White
                        strongSelf.navigationBar?.updatePresentationData(NavigationBarPresentationData(theme: GalleryController.darkNavigationTheme, strings: NavigationBarStrings(presentationStrings: strongSelf.presentationData.strings)))
                        strongSelf.galleryNode.backgroundNode.backgroundColor = UIColor.black
                        strongSelf.galleryNode.isBackgroundExtendedOverNavigationBar = true
                    case .light:
                        strongSelf.statusBar.statusBarStyle = .Black
                        strongSelf.navigationBar?.updatePresentationData(NavigationBarPresentationData(theme: GalleryController.darkNavigationTheme, strings: NavigationBarStrings(presentationStrings: strongSelf.presentationData.strings)))
                        strongSelf.galleryNode.backgroundNode.backgroundColor = UIColor(rgb: 0xbdbdc2)
                        strongSelf.galleryNode.isBackgroundExtendedOverNavigationBar = false
                }
            }
        }))
        
        let mediaManager = context.sharedContext.mediaManager
        self.hiddenMediaManagerIndex = mediaManager.galleryHiddenMediaManager.addSource(self._hiddenMedia.get()
        |> map { messageIdAndMedia in
            if let (messageId, media) = messageIdAndMedia {
                return .chat(context.account.id, messageId, media)
            } else {
                return nil
            }
        })
        
        performActionImpl = { [weak self] action in
            if let strongSelf = self {
                strongSelf.dismiss(forceAway: false)
                switch action {
                    case let .url(url, concealed):
                        strongSelf.actionInteraction?.openUrl(url, concealed)
                    case let .textMention(mention):
                        strongSelf.actionInteraction?.openPeerMention(mention)
                    case let .peerMention(peerId, _):
                        strongSelf.actionInteraction?.openPeer(peerId)
                    case let .botCommand(command):
                        strongSelf.actionInteraction?.openBotCommand(command)
                    case let .hashtag(peerName, hashtag):
                        strongSelf.actionInteraction?.openHashtag(peerName, hashtag)
                }
            }
        }
        
        openActionOptionsImpl = { [weak self] action in
            if let strongSelf = self {
                switch action {
                case let .url(url, _):
                    var cleanUrl = url
                    var canAddToReadingList = true
                    let canOpenIn = availableOpenInOptions(context: strongSelf.context, item: .url(url: url)).count > 1
                    let mailtoString = "mailto:"
                    let telString = "tel:"
                    var openText = strongSelf.presentationData.strings.Conversation_LinkDialogOpen
                    var phoneNumber: String?
                    if cleanUrl.hasPrefix(mailtoString) {
                        canAddToReadingList = false
                        cleanUrl = String(cleanUrl[cleanUrl.index(cleanUrl.startIndex, offsetBy: mailtoString.distance(from: mailtoString.startIndex, to: mailtoString.endIndex))...])
                    } else if cleanUrl.hasPrefix(telString) {
                        canAddToReadingList = false
                        phoneNumber = String(cleanUrl[cleanUrl.index(cleanUrl.startIndex, offsetBy: telString.distance(from: telString.startIndex, to: telString.endIndex))...])
                        cleanUrl = phoneNumber!
                        openText = strongSelf.presentationData.strings.UserInfo_PhoneCall
                    } else if canOpenIn {
                        openText = strongSelf.presentationData.strings.Conversation_FileOpenIn
                    }
                    let actionSheet = ActionSheetController(presentationTheme: strongSelf.presentationData.theme)
                    
                    var items: [ActionSheetItem] = []
                    items.append(ActionSheetTextItem(title: cleanUrl))
                    items.append(ActionSheetButtonItem(title: openText, color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        if let strongSelf = self {
                            if canOpenIn {
                                strongSelf.actionInteraction?.openUrlIn(url)
                            } else {
                                strongSelf.dismiss(forceAway: false)
                                strongSelf.actionInteraction?.openUrl(url, false)
                            }
                        }
                    }))
                    if let phoneNumber = phoneNumber {
                        items.append(ActionSheetButtonItem(title: strongSelf.presentationData.strings.Conversation_AddContact, color: .accent, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                            if let strongSelf = self {
                                strongSelf.dismiss(forceAway: false)
                                strongSelf.actionInteraction?.addContact(phoneNumber)
                            }
                        }))
                    }
                    items.append(ActionSheetButtonItem(title: canAddToReadingList ? strongSelf.presentationData.strings.ShareMenu_CopyShareLink : strongSelf.presentationData.strings.Conversation_ContextMenuCopy, color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        UIPasteboard.general.string = cleanUrl
                    }))
                    if canAddToReadingList {
                        items.append(ActionSheetButtonItem(title: strongSelf.presentationData.strings.Conversation_AddToReadingList, color: .accent, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                            if let link = URL(string: url) {
                                let _ = try? SSReadingList.default()?.addItem(with: link, title: nil, previewText: nil)
                            }
                        }))
                    }
                    actionSheet.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [
                        ActionSheetButtonItem(title: strongSelf.presentationData.strings.Common_Cancel, color: .accent, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                        })
                    ])])
                    strongSelf.present(actionSheet, in: .window(.root))
                case let .peerMention(peerId, mention):
                    let actionSheet = ActionSheetController(presentationTheme: strongSelf.presentationData.theme)
                    var items: [ActionSheetItem] = []
                    if !mention.isEmpty {
                        items.append(ActionSheetTextItem(title: mention))
                    }
                    items.append(ActionSheetButtonItem(title: strongSelf.presentationData.strings.Conversation_LinkDialogOpen, color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        if let strongSelf = self {
                            strongSelf.dismiss(forceAway: false)
                            strongSelf.actionInteraction?.openPeer(peerId)
                        }
                    }))
                    if !mention.isEmpty {
                        items.append(ActionSheetButtonItem(title: strongSelf.presentationData.strings.Conversation_LinkDialogCopy, color: .accent, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                            UIPasteboard.general.string = mention
                        }))
                    }
                    actionSheet.setItemGroups([ActionSheetItemGroup(items:items), ActionSheetItemGroup(items: [
                        ActionSheetButtonItem(title: strongSelf.presentationData.strings.Common_Cancel, color: .accent, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                        })
                        ])])
                    strongSelf.present(actionSheet, in: .window(.root))
                case let .textMention(mention):
                    let actionSheet = ActionSheetController(presentationTheme: strongSelf.presentationData.theme)
                    actionSheet.setItemGroups([ActionSheetItemGroup(items: [
                        ActionSheetTextItem(title: mention),
                        ActionSheetButtonItem(title: strongSelf.presentationData.strings.Conversation_LinkDialogOpen, color: .accent, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                            if let strongSelf = self {
                                strongSelf.dismiss(forceAway: false)
                                strongSelf.actionInteraction?.openPeerMention(mention)
                            }
                        }),
                        ActionSheetButtonItem(title: strongSelf.presentationData.strings.Conversation_LinkDialogCopy, color: .accent, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                            UIPasteboard.general.string = mention
                        })
                        ]), ActionSheetItemGroup(items: [
                            ActionSheetButtonItem(title: strongSelf.presentationData.strings.Common_Cancel, color: .accent, action: { [weak actionSheet] in
                                actionSheet?.dismissAnimated()
                            })
                            ])])
                    strongSelf.present(actionSheet, in: .window(.root))
                case let .botCommand(command):
                    let actionSheet = ActionSheetController(presentationTheme: strongSelf.presentationData.theme)
                    var items: [ActionSheetItem] = []
                    items.append(ActionSheetTextItem(title: command))
                    items.append(ActionSheetButtonItem(title: strongSelf.presentationData.strings.Conversation_LinkDialogCopy, color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        UIPasteboard.general.string = command
                    }))
                    actionSheet.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [
                        ActionSheetButtonItem(title: strongSelf.presentationData.strings.Common_Cancel, color: .accent, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                        })
                        ])])
                    strongSelf.present(actionSheet, in: .window(.root))
                case let .hashtag(peerName, hashtag):
                    let actionSheet = ActionSheetController(presentationTheme: strongSelf.presentationData.theme)
                    actionSheet.setItemGroups([ActionSheetItemGroup(items: [
                        ActionSheetTextItem(title: hashtag),
                        ActionSheetButtonItem(title: strongSelf.presentationData.strings.Conversation_LinkDialogOpen, color: .accent, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                            if let strongSelf = self {
                                strongSelf.dismiss(forceAway: false)
                                strongSelf.actionInteraction?.openHashtag(peerName, hashtag)
                            }
                        }),
                        ActionSheetButtonItem(title: strongSelf.presentationData.strings.Conversation_LinkDialogCopy, color: .accent, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                            UIPasteboard.general.string = hashtag
                        })
                        ]), ActionSheetItemGroup(items: [
                            ActionSheetButtonItem(title: strongSelf.presentationData.strings.Common_Cancel, color: .accent, action: { [weak actionSheet] in
                                actionSheet?.dismissAnimated()
                            })
                        ])
                    ])
                    strongSelf.present(actionSheet, in: .window(.root))
                }
            }
        }
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.accountInUseDisposable.dispose()
        self.disposable.dispose()
        self.centralItemAttributesDisposable.dispose()
        if let hiddenMediaManagerIndex = self.hiddenMediaManagerIndex {
            self.context.sharedContext.mediaManager.galleryHiddenMediaManager.removeSource(hiddenMediaManagerIndex)
        }
    }
    
    @objc func donePressed() {
        self.dismiss(forceAway: false)
    }
    
    private func dismiss(forceAway: Bool) {
        var animatedOutNode = true
        var animatedOutInterface = false
        
        let completion = { [weak self] in
            if animatedOutNode && animatedOutInterface {
                self?._hiddenMedia.set(.single(nil))
                self?.presentingViewController?.dismiss(animated: false, completion: nil)
            }
        }
        
        if let centralItemNode = self.galleryNode.pager.centralItemNode(), let presentationArguments = self.presentationArguments as? GalleryControllerPresentationArguments {
            if case let .MessageEntry(message, _, _, _, _) = self.entries[centralItemNode.index] {
                if let (media, _) = mediaForMessage(message: message), let transitionArguments = presentationArguments.transitionArguments(message.id, media), !forceAway {
                    animatedOutNode = false
                    centralItemNode.animateOut(to: transitionArguments.transitionNode, addToTransitionSurface: transitionArguments.addToTransitionSurface, completion: {
                        animatedOutNode = true
                        completion()
                    })
                }
            }
        }
        
        self.galleryNode.animateOut(animateContent: animatedOutNode, completion: {
            animatedOutInterface = true
            completion()
        })
    }
    
    override func loadDisplayNode() {
        let controllerInteraction = GalleryControllerInteraction(presentController: { [weak self] controller, arguments in
            if let strongSelf = self {
                strongSelf.present(controller, in: .window(.root), with: arguments, blockInteraction: true)
            }
        }, dismissController: { [weak self] in
            self?.dismiss(forceAway: true)
        }, replaceRootController: { [weak self] controller, ready in
            if let strongSelf = self {
                strongSelf.replaceRootController(controller, ready)
            }
        })
        self.displayNode = GalleryControllerNode(controllerInteraction: controllerInteraction)
        self.displayNodeDidLoad()
        
        self.galleryNode.statusBar = self.statusBar
        self.galleryNode.navigationBar = self.navigationBar
        
        self.galleryNode.transitionDataForCentralItem = { [weak self] in
            if let strongSelf = self {
                if let centralItemNode = strongSelf.galleryNode.pager.centralItemNode(), let presentationArguments = strongSelf.presentationArguments as? GalleryControllerPresentationArguments {
                    if case let .MessageEntry(message, _, _, _, _) = strongSelf.entries[centralItemNode.index] {
                        if let (media, _) = mediaForMessage(message: message), let transitionArguments = presentationArguments.transitionArguments(message.id, media) {
                            return (transitionArguments.transitionNode, transitionArguments.addToTransitionSurface)
                        }
                    }
                }
            }
            return nil
        }
        self.galleryNode.dismiss = { [weak self] in
            self?._hiddenMedia.set(.single(nil))
            self?.presentingViewController?.dismiss(animated: false, completion: nil)
        }
        
        self.galleryNode.beginCustomDismiss = { [weak self] in
            if let strongSelf = self {
                strongSelf._hiddenMedia.set(.single(nil))
                
                var animatedOutNode = true
                var animatedOutInterface = false
                
                let completion = {
                    if animatedOutNode && animatedOutInterface {
                        //self?.presentingViewController?.dismiss(animated: false, completion: nil)
                    }
                }
                
                strongSelf.galleryNode.animateOut(animateContent: animatedOutNode, completion: {
                    animatedOutInterface = true
                    //completion()
                })
            }
        }
        
        self.galleryNode.completeCustomDismiss = { [weak self] in
            self?._hiddenMedia.set(.single(nil))
            self?.presentingViewController?.dismiss(animated: false, completion: nil)
        }
        
        let baseNavigationController = self.baseNavigationController
        self.galleryNode.baseNavigationController = { [weak baseNavigationController] in
            return baseNavigationController
        }
        
        var items: [GalleryItem] = []
        var centralItemIndex: Int?
        for entry in self.entries {
            if let item = galleryItemForEntry(context: context, presentationData: self.presentationData, entry: entry, streamVideos: self.streamVideos, fromPlayingVideo: self.fromPlayingVideo, landscape: self.landscape, performAction: self.performAction, openActionOptions: self.openActionOptions) {
                if case let .MessageEntry(message, _, _, _, _) = entry, message.stableId == self.centralEntryStableId {
                    centralItemIndex = items.count
                }
                items.append(item)
            }
        }
        
        self.galleryNode.pager.replaceItems(items, centralItemIndex: centralItemIndex)
        
        self.galleryNode.pager.centralItemIndexUpdated = { [weak self] index in
            if let strongSelf = self {
                var hiddenItem: (MessageId, Media)?
                if let index = index {
                    if case let .MessageEntry(message, _, _, _, _) = strongSelf.entries[index], let (media, _) = mediaForMessage(message: message) {
                        hiddenItem = (message.id, media)
                    }
                    
                    if let node = strongSelf.galleryNode.pager.centralItemNode() {
                        strongSelf.centralItemTitle.set(node.title())
                        strongSelf.centralItemTitleView.set(node.titleView())
                        strongSelf.centralItemRightBarButtonItem.set(node.rightBarButtonItem())
                        strongSelf.centralItemNavigationStyle.set(node.navigationStyle())
                        strongSelf.centralItemFooterContentNode.set(node.footerContent())
                    }
                }
                if strongSelf.didSetReady {
                    strongSelf._hiddenMedia.set(.single(hiddenItem))
                }
            }
        }
        
        if !self.entries.isEmpty && !self.didSetReady {
            if self.temporaryDoNotWaitForReady {
                self.didSetReady = true
                self._ready.set(.single(true))
            } else {
                let ready = self.galleryNode.pager.ready() |> timeout(2.0, queue: Queue.mainQueue(), alternate: .single(Void())) |> afterNext { [weak self] _ in
                    self?.didSetReady = true
                }
                self._ready.set(ready |> map { true })
            }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        var nodeAnimatesItself = false
        
        if let centralItemNode = self.galleryNode.pager.centralItemNode() {
            if case let .MessageEntry(message, _, _, _, _) = self.entries[centralItemNode.index] {
                self.centralItemTitle.set(centralItemNode.title())
                self.centralItemTitleView.set(centralItemNode.titleView())
                self.centralItemRightBarButtonItem.set(centralItemNode.rightBarButtonItem())
                self.centralItemNavigationStyle.set(centralItemNode.navigationStyle())
                self.centralItemFooterContentNode.set(centralItemNode.footerContent())
                
                if let (media, _) = mediaForMessage(message: message) {
                    if let presentationArguments = self.presentationArguments as? GalleryControllerPresentationArguments, let transitionArguments = presentationArguments.transitionArguments(message.id, media) {
                        nodeAnimatesItself = true
                        centralItemNode.activateAsInitial()
                        
                        if presentationArguments.animated {
                            centralItemNode.animateIn(from: transitionArguments.transitionNode, addToTransitionSurface: transitionArguments.addToTransitionSurface)
                        }
                        
                        self._hiddenMedia.set(.single((message.id, media)))
                    } else if self.isPresentedInPreviewingContext() {
                        centralItemNode.activateAsInitial()
                    }
                }
            }
        }
        
        if !self.isPresentedInPreviewingContext() {
            self.galleryNode.setControlsHidden(self.landscape, animated: false)
            if let presentationArguments = self.presentationArguments as? GalleryControllerPresentationArguments {
                if presentationArguments.animated {
                    self.galleryNode.animateIn(animateContent: !nodeAnimatesItself)
                }
            }
        }
        
        self.accountInUseDisposable.set(self.context.sharedContext.setAccountUserInterfaceInUse(self.context.account.id))
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        self.accountInUseDisposable.set(nil)
    }
    
    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        
        self.galleryNode.frame = CGRect(origin: CGPoint(), size: layout.size)
        self.galleryNode.containerLayoutUpdated(layout, navigationBarHeight: self.navigationHeight, transition: transition)
        
        if !self.adjustedForInitialPreviewingLayout && self.isPresentedInPreviewingContext() {
            self.adjustedForInitialPreviewingLayout = true
            self.galleryNode.setControlsHidden(true, animated: false)
            if let centralItemNode = self.galleryNode.pager.centralItemNode(), let itemSize = centralItemNode.contentSize() {
                self.preferredContentSize = itemSize.aspectFitted(self.view.bounds.size)
                self.containerLayoutUpdated(ContainerViewLayout(size: self.preferredContentSize, metrics: LayoutMetrics(), intrinsicInsets: UIEdgeInsets(), safeInsets: UIEdgeInsets(), statusBarHeight: nil, inputHeight: nil, standardInputHeight: 216.0, inputHeightIsInteractivellyChanging: false, inVoiceOver: false), transition: .immediate)
            }
        }
    }
}
