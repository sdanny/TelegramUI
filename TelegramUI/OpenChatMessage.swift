import Foundation
import Display
import AsyncDisplayKit
import Postbox
import TelegramCore
import SwiftSignalKit
import PassKit

private enum ChatMessageGalleryControllerData {
    case url(String)
    case pass(TelegramMediaFile)
    case instantPage(InstantPageGalleryController, Int, Media)
    case map(TelegramMediaMap)
    case stickerPack(StickerPackReference)
    case audio(TelegramMediaFile)
    case document(TelegramMediaFile)
    case gallery(GalleryController)
    case secretGallery(SecretMediaPreviewController)
    case other(Media)
    case chatAvatars(AvatarGalleryController, Media)
}

private func chatMessageGalleryControllerData(context: AccountContext, message: Message, navigationController: NavigationController?, standalone: Bool, reverseMessageGalleryOrder: Bool, mode: ChatControllerInteractionOpenMessageMode, synchronousLoad: Bool, actionInteraction: GalleryControllerActionInteraction?) -> ChatMessageGalleryControllerData? {
    var galleryMedia: Media?
    var otherMedia: Media?
    var instantPageMedia: (TelegramMediaWebpage, [InstantPageGalleryEntry])?
    for media in message.media {
        if let action = media as? TelegramMediaAction {
            switch action.action {
            case let .photoUpdated(image):
                if let peer = messageMainPeer(message), let image = image {
                    let promise: Promise<[AvatarGalleryEntry]> = Promise([AvatarGalleryEntry.image(image.reference, image.representations.map({ ImageRepresentationWithReference(representation: $0, reference: .media(media: .message(message: MessageReference(message), media: media), resource: $0.resource)) }), peer, message.timestamp, nil)])
                    let galleryController = AvatarGalleryController(context: context, peer: peer, remoteEntries: promise, replaceRootController: { controller, ready in
                        
                    })
                    return .chatAvatars(galleryController, image)
                }
            default:
                break
            }
        } else if let file = media as? TelegramMediaFile {
            galleryMedia = file
        } else if let image = media as? TelegramMediaImage {
            galleryMedia = image
        } else if let webpage = media as? TelegramMediaWebpage, case let .Loaded(content) = webpage.content {
                if let file = content.file {
                    galleryMedia = file
                } else if let image = content.image {
                    if ["photo", "document", "video", "gif"].contains(content.type) {
                        galleryMedia = image
                    }
                }
            
            if let instantPage = content.instantPage, let galleryMedia = galleryMedia {
                switch instantPageType(of: content) {
                    case .album:
                        let medias = instantPageGalleryMedia(webpageId: webpage.webpageId, page: instantPage, galleryMedia: galleryMedia)
                        if medias.count > 1 {
                            instantPageMedia = (webpage, medias)
                        }      
                    default:
                        break
                }
            }
        } else if let mapMedia = media as? TelegramMediaMap {
            galleryMedia = mapMedia
        } else if let contactMedia = media as? TelegramMediaContact {
            otherMedia = contactMedia
        }
    }
    
    var stream = false
    var fromPlayingVideo = false
    var landscape = false
    
    if case .stream = mode {
        stream = true
    }
    if case .automaticPlayback = mode {
        fromPlayingVideo = true
    }
    if case .landscape = mode {
        fromPlayingVideo = true
        landscape = true
    }
    
    if let (webPage, instantPageMedia) = instantPageMedia, let galleryMedia = galleryMedia {
        var centralIndex: Int = 0
        for i in 0 ..< instantPageMedia.count {
            if instantPageMedia[i].media.media.id == galleryMedia.id {
                centralIndex = i
                break
            }
        }
        
        let gallery = InstantPageGalleryController(context: context, webPage: webPage, message: message, entries: instantPageMedia, centralIndex: centralIndex, fromPlayingVideo: fromPlayingVideo, landscape: landscape, replaceRootController: { [weak navigationController] controller, ready in
            if let navigationController = navigationController {
                navigationController.replaceTopController(controller, animated: false, ready: ready)
            }
        }, baseNavigationController: navigationController)
        return .instantPage(gallery, centralIndex, galleryMedia)
    } else if let galleryMedia = galleryMedia {
        if let mapMedia = galleryMedia as? TelegramMediaMap {
            return .map(mapMedia)
        } else if let file = galleryMedia as? TelegramMediaFile, file.isSticker {
            for attribute in file.attributes {
                if case let .Sticker(_, reference, _) = attribute {
                    if let reference = reference {
                        return .stickerPack(reference)
                    }
                    break
                }
            }
        } else if let file = galleryMedia as? TelegramMediaFile, file.isMusic || file.isVoice || file.isInstantVideo {
            return .audio(file)
        } else if let file = galleryMedia as? TelegramMediaFile, file.mimeType == "application/vnd.apple.pkpass" || (file.fileName != nil && file.fileName!.lowercased().hasSuffix(".pkpass")) {
            return .pass(file)
        } else {
            if let file = galleryMedia as? TelegramMediaFile {
                if let fileName = file.fileName {
                    let ext = (fileName as NSString).pathExtension.lowercased()
                    if ext == "wav" || ext == "opus" {
                        return .audio(file)
                    }
                    #if DEBUG
                    if ext == "mkv" {
                        let gallery = GalleryController(context: context, source: standalone ? .standaloneMessage(message) : .peerMessagesAtId(message.id), invertItemOrder: reverseMessageGalleryOrder, streamSingleVideo: stream, fromPlayingVideo: fromPlayingVideo, landscape: landscape, synchronousLoad: synchronousLoad, replaceRootController: { [weak navigationController] controller, ready in
                            navigationController?.replaceTopController(controller, animated: false, ready: ready)
                            }, baseNavigationController: navigationController, actionInteraction: actionInteraction)
                        return .gallery(gallery)
                    }
                    #endif
                }
                
                if !file.isVideo, !internalDocumentItemSupportsMimeType(file.mimeType, fileName: file.fileName) {
                    return .document(file)
                }
            }
            
            if message.containsSecretMedia {
                let gallery = SecretMediaPreviewController(context: context, messageId: message.id)
                return .secretGallery(gallery)
            } else {
                let gallery = GalleryController(context: context, source: standalone ? .standaloneMessage(message) : .peerMessagesAtId(message.id), invertItemOrder: reverseMessageGalleryOrder, streamSingleVideo: stream, fromPlayingVideo: fromPlayingVideo, landscape: landscape, synchronousLoad: synchronousLoad, replaceRootController: { [weak navigationController] controller, ready in
                    navigationController?.replaceTopController(controller, animated: false, ready: ready)
                    }, baseNavigationController: navigationController, actionInteraction: actionInteraction)
                gallery.temporaryDoNotWaitForReady = fromPlayingVideo
                return .gallery(gallery)
            }
        }
    }
    if let otherMedia = otherMedia {
        return .other(otherMedia)
    } else {
        return nil
    }
}

enum ChatMessagePreviewControllerData {
    case instantPage(InstantPageGalleryController, Int, Media)
    case gallery(GalleryController)
}

func chatMessagePreviewControllerData(context: AccountContext, message: Message, standalone: Bool, reverseMessageGalleryOrder: Bool, navigationController: NavigationController?) -> ChatMessagePreviewControllerData? {
    if let mediaData = chatMessageGalleryControllerData(context: context, message: message, navigationController: navigationController, standalone: standalone, reverseMessageGalleryOrder: reverseMessageGalleryOrder, mode: .default, synchronousLoad: true, actionInteraction: nil) {
        switch mediaData {
            case let .gallery(gallery):
                return .gallery(gallery)
            case let .instantPage(gallery, centralIndex, galleryMedia):
                return .instantPage(gallery, centralIndex, galleryMedia)
            default:
                break
        }
    }
    return nil
}

func openChatMessage(context: AccountContext, message: Message, standalone: Bool, reverseMessageGalleryOrder: Bool, mode: ChatControllerInteractionOpenMessageMode = .default, navigationController: NavigationController?, modal: Bool = false, dismissInput: @escaping () -> Void, present: @escaping (ViewController, Any?) -> Void, transitionNode: @escaping (MessageId, Media) -> (ASDisplayNode, () -> (UIView?, UIView?))?, addToTransitionSurface: @escaping (UIView) -> Void, openUrl: @escaping (String) -> Void, openPeer: @escaping (Peer, ChatControllerInteractionNavigateToPeer) -> Void, callPeer: @escaping (PeerId) -> Void, enqueueMessage: @escaping (EnqueueMessage) -> Void, sendSticker: ((FileMediaReference) -> Void)?, setupTemporaryHiddenMedia: @escaping (Signal<InstantPageGalleryEntry?, NoError>, Int, Media) -> Void, chatAvatarHiddenMedia: @escaping (Signal<MessageId?, NoError>, Media) -> Void, actionInteraction: GalleryControllerActionInteraction? = nil) -> Bool {
    if let mediaData = chatMessageGalleryControllerData(context: context, message: message, navigationController: navigationController, standalone: standalone, reverseMessageGalleryOrder: reverseMessageGalleryOrder, mode: mode, synchronousLoad: false, actionInteraction: actionInteraction) {
        switch mediaData {
            case let .url(url):
                openUrl(url)
                return true
            case let .pass(file):
                let _ = (context.account.postbox.mediaBox.resourceData(file.resource, option: .complete(waitUntilFetchStatus: true))
                |> take(1)
                |> deliverOnMainQueue).start(next: { data in
                    guard let navigationController = navigationController else {
                        return
                    }
                    if data.complete, let content = try? Data(contentsOf: URL(fileURLWithPath: data.path)) {
                        var error: NSError?
                        let pass = PKPass(data: content, error: &error)
                        if error == nil {
                            let controller = PKAddPassesViewController(pass: pass)
                            if let window = navigationController.view.window {
                                controller.popoverPresentationController?.sourceView = window
                                controller.popoverPresentationController?.sourceRect = CGRect(origin: CGPoint(x: window.bounds.width / 2.0, y: window.bounds.size.height - 1.0), size: CGSize(width: 1.0, height: 1.0))
                                window.rootViewController?.present(controller, animated: true)
                            }
                        }
                    }
                })
                return true
            case let .instantPage(gallery, centralIndex, galleryMedia):
                setupTemporaryHiddenMedia(gallery.hiddenMedia, centralIndex, galleryMedia)
                
                dismissInput()
                present(gallery, InstantPageGalleryControllerPresentationArguments(transitionArguments: { entry in
                    var selectedTransitionNode: (ASDisplayNode, () -> (UIView?, UIView?))?
                    if entry.index == centralIndex {
                        selectedTransitionNode = transitionNode(message.id, galleryMedia)
                    }
                    if let selectedTransitionNode = selectedTransitionNode {
                        return GalleryTransitionArguments(transitionNode: selectedTransitionNode, addToTransitionSurface: addToTransitionSurface)
                    }
                    return nil
                }))
                return true
            case let .map(mapMedia):
                dismissInput()
                
                let controller = legacyLocationController(message: message, mapMedia: mapMedia, context: context, isModal: modal, openPeer: { peer in
                    openPeer(peer, .info)
                }, sendLiveLocation: { coordinate, period in
                    let outMessage: EnqueueMessage = .message(text: "", attributes: [], mediaReference: .standalone(media: TelegramMediaMap(latitude: coordinate.latitude, longitude: coordinate.longitude, geoPlace: nil, venue: nil, liveBroadcastingTimeout: period)), replyToMessageId: nil, localGroupingKey: nil)
                    enqueueMessage(outMessage)
                }, stopLiveLocation: {
                    context.liveLocationManager?.cancelLiveLocation(peerId: message.id.peerId)
                }, openUrl: openUrl)
                
                if modal {
                    present(controller, nil)
                } else {
                    navigationController?.pushViewController(controller)
                }
                return true
            case let .stickerPack(reference):
                let controller = StickerPackPreviewController(context: context, stickerPack: reference, parentNavigationController: navigationController)
                controller.sendSticker = sendSticker
                dismissInput()
                present(controller, nil)
                return true
            case let .document(file):
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                if let rootController = navigationController?.view.window?.rootViewController {
                    presentDocumentPreviewController(rootController: rootController, theme: presentationData.theme, strings: presentationData.strings, postbox: context.account.postbox, file: file)
                }
                //present(ShareController(account: account, subject: .messages([message]), showInChat: nil, externalShare: true, immediateExternalShare: true), nil)
                return true
            case let .audio(file):
                let location: PeerMessagesPlaylistLocation
                let playerType: MediaManagerPlayerType
                if (file.isVoice || file.isInstantVideo) && message.tags.contains(.voiceOrInstantVideo) {
                    if standalone {
                        location = .recentActions(message)
                    } else {
                        location = .messages(peerId: message.id.peerId, tagMask: .voiceOrInstantVideo, at: message.id)
                    }
                    playerType = .voice
                } else if file.isMusic && message.tags.contains(.music) {
                    if standalone {
                            location = .recentActions(message)
                    } else {
                        location = .messages(peerId: message.id.peerId, tagMask: .music, at: message.id)
                    }
                    playerType = .music
                } else {
                    if standalone {
                        location = .recentActions(message)
                    } else {
                        location = .singleMessage(message.id)
                    }
                    playerType = (file.isVoice || file.isInstantVideo) ? .voice : .music
                }
                context.sharedContext.mediaManager.setPlaylist((context.account, PeerMessagesMediaPlaylist(postbox: context.account.postbox, network: context.account.network, location: location)), type: playerType)
                return true
            case let .gallery(gallery):
                dismissInput()
                present(gallery, GalleryControllerPresentationArguments(transitionArguments: { messageId, media in
                    let selectedTransitionNode = transitionNode(messageId, media)
                    if let selectedTransitionNode = selectedTransitionNode {
                        return GalleryTransitionArguments(transitionNode: selectedTransitionNode, addToTransitionSurface: addToTransitionSurface)
                    }
                    return nil
                }))
                return true
            case let .secretGallery(gallery):
                dismissInput()
                present(gallery, GalleryControllerPresentationArguments(transitionArguments: { messageId, media in
                    let selectedTransitionNode = transitionNode(messageId, media)
                    if let selectedTransitionNode = selectedTransitionNode {
                        return GalleryTransitionArguments(transitionNode: selectedTransitionNode, addToTransitionSurface: addToTransitionSurface)
                    }
                    return nil
                }))
                return true
            case let .other(otherMedia):
                if let contact = otherMedia as? TelegramMediaContact {
                    let _ = (context.account.postbox.transaction { transaction -> (Peer?, Bool?) in
                        if let peerId = contact.peerId {
                            return (transaction.getPeer(peerId), transaction.isPeerContact(peerId: peerId))
                        } else {
                            return (nil, nil)
                        }
                    } |> deliverOnMainQueue).start(next: { peer, isContact in
                        let contactData: DeviceContactExtendedData
                        if let vCard = contact.vCardData, let vCardData = vCard.data(using: .utf8), let parsed = DeviceContactExtendedData(vcard: vCardData) {
                            contactData = parsed
                        } else {
                            contactData = DeviceContactExtendedData(basicData: DeviceContactBasicData(firstName: contact.firstName, lastName: contact.lastName, phoneNumbers: [DeviceContactPhoneNumberData(label: "_$!<Home>!$_", value: contact.phoneNumber)]), middleName: "", prefix: "", suffix: "", organization: "", jobTitle: "", department: "", emailAddresses: [], urls: [], addresses: [], birthdayDate: nil, socialProfiles: [], instantMessagingProfiles: [])
                        }
                        let controller = deviceContactInfoController(context: context, subject: .vcard(peer, nil, contactData))
                        navigationController?.pushViewController(controller)
                        
                        guard let peer = peer else {
                            return
                        }
                        
                        /*let presentationData = account.telegramApplicationContext.currentPresentationData.with { $0 }
                        let controller = ActionSheetController(presentationTheme: presentationData.theme)
                        let dismissAction: () -> Void = { [weak controller] in
                            controller?.dismissAnimated()
                        }
                        var items: [ActionSheetItem] = []
                        
                        if let peerId = contact.peerId {
                            items.append(ActionSheetButtonItem(title: presentationData.strings.Conversation_SendMessage, action: {
                                dismissAction()
                                
                                openPeer(peer, .chat(textInputState: nil, messageId: nil))
                            }))
                            if let isContact = isContact, !isContact {
                                items.append(ActionSheetButtonItem(title: presentationData.strings.Conversation_AddContact, action: {
                                    dismissAction()
                                    let _ = addContactPeerInteractively(account: account, peerId: peerId, phone: contact.phoneNumber).start()
                                }))
                            }
                            items.append(ActionSheetButtonItem(title: presentationData.strings.UserInfo_TelegramCall, action: {
                                dismissAction()
                                callPeer(peerId)
                            }))
                        }
                        items.append(ActionSheetButtonItem(title: presentationData.strings.UserInfo_PhoneCall, action: {
                            dismissAction()
                            account.telegramApplicationcontext.sharedContext.applicationBindings.openUrl("tel:\(formatPhoneNumber(contact.phoneNumber).replacingOccurrences(of: " ", with: ""))")
                        }))
                        controller.setItemGroups([
                            ActionSheetItemGroup(items: items),
                            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: { dismissAction() })])
                            ])
                        dismissInput()
                        present(controller, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))*/
                    })
                    return true
                }
        case let .chatAvatars(controller, media):
            dismissInput()
            chatAvatarHiddenMedia(controller.hiddenMedia |> map { value -> MessageId? in
                if value != nil {
                    return message.id
                } else {
                    return nil
                }
            }, media)
            
            present(controller, AvatarGalleryControllerPresentationArguments(transitionArguments: { entry in
                if let selectedTransitionNode = transitionNode(message.id, media) {
                    return GalleryTransitionArguments(transitionNode: selectedTransitionNode, addToTransitionSurface: addToTransitionSurface)
                }
                return nil
            }))
        }
    }
    return false
}

func openChatInstantPage(context: AccountContext, message: Message, sourcePeerType: MediaAutoDownloadPeerType?, navigationController: NavigationController) {
    for media in message.media {
        if let webpage = media as? TelegramMediaWebpage, case let .Loaded(content) = webpage.content {
            if let _ = content.instantPage {
                var textUrl: String?
                if let pageUrl = URL(string: content.url) {
                    inner: for attribute in message.attributes {
                        if let attribute = attribute as? TextEntitiesMessageAttribute {
                            for entity in attribute.entities {
                                switch entity.type {
                                case let .TextUrl(url):
                                    if let parsedUrl = URL(string: url) {
                                        if pageUrl.scheme == parsedUrl.scheme && pageUrl.host == parsedUrl.host && pageUrl.path == parsedUrl.path {
                                            textUrl = url
                                        }
                                    }
                                case .Url:
                                    let nsText = message.text as NSString
                                    var entityRange = NSRange(location: entity.range.lowerBound, length: entity.range.upperBound - entity.range.lowerBound)
                                    if entityRange.location + entityRange.length > nsText.length {
                                        entityRange.location = max(0, nsText.length - entityRange.length)
                                        entityRange.length = nsText.length - entityRange.location
                                    }
                                    let url = nsText.substring(with: entityRange)
                                    if let parsedUrl = URL(string: url) {
                                        if pageUrl.scheme == parsedUrl.scheme && pageUrl.host == parsedUrl.host && pageUrl.path == parsedUrl.path {
                                            textUrl = url
                                        }
                                    }
                                default:
                                    break
                                }
                            }
                            break inner
                        }
                    }
                }
                var anchor: String?
                if let textUrl = textUrl, let anchorRange = textUrl.range(of: "#") {
                    anchor = String(textUrl[anchorRange.upperBound...])
                }
                
                let pageController = InstantPageController(context: context, webPage: webpage, sourcePeerType: sourcePeerType ?? .channel, anchor: anchor)
                navigationController.pushViewController(pageController)
            }
            break
        }
    }
}

func openChatWallpaper(context: AccountContext, message: Message, present: @escaping (ViewController, Any?) -> Void) {
    for media in message.media {
        if let webpage = media as? TelegramMediaWebpage, case let .Loaded(content) = webpage.content {
            let _ = (resolveUrl(account: context.account, url: content.url)
            |> deliverOnMainQueue).start(next: { resolvedUrl in
                if case let .wallpaper(parameter) = resolvedUrl {
                    let source: WallpaperListSource
                    switch parameter {
                        case let .slug(slug, options, color, intensity):
                            source = .slug(slug, content.file, options, color, intensity, message)
                        case let .color(color):
                            source = .wallpaper(.color(Int32(color.rgb)), nil, nil, nil, message)
                    }
                    
                    let controller = WallpaperGalleryController(context: context, source: source)
                    present(controller, nil)
                }
            })
        }
    }
}
