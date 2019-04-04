import Foundation
import Display
import AsyncDisplayKit
import Postbox
import TelegramCore
import SwiftSignalKit

public struct ShareControllerAction {
    let title: String
    let action: () -> Void
}

public enum ShareControllerPreferredAction {
    case `default`
    case saveToCameraRoll
    case custom(action: ShareControllerAction)
}

public enum ShareControllerExternalStatus {
    case preparing
    case progress(Float)
    case done
}

public enum ShareControllerSubject {
    case url(String)
    case text(String)
    case quote(text: String, url: String)
    case messages([Message])
    case image([ImageRepresentationWithReference])
    case media(AnyMediaReference)
    case mapMedia(TelegramMediaMap)
    case fromExternal(([PeerId], String, Account) -> Signal<ShareControllerExternalStatus, NoError>)
}

private enum ExternalShareItem {
    case text(String)
    case url(URL)
    case image(UIImage)
    case file(URL, String, String)
}

private enum ExternalShareItemStatus {
    case progress
    case done(ExternalShareItem)
}

private enum ExternalShareResourceStatus {
    case progress
    case done(MediaResourceData)
}

private func collectExternalShareResource(postbox: Postbox, resourceReference: MediaResourceReference, statsCategory: MediaResourceStatsCategory) -> Signal<ExternalShareResourceStatus, NoError> {
    return Signal { subscriber in
        let fetched = fetchedMediaResource(postbox: postbox, reference: resourceReference, statsCategory: statsCategory).start()
        let data = postbox.mediaBox.resourceData(resourceReference.resource, option: .complete(waitUntilFetchStatus: false)).start(next: { value in
            if value.complete {
                subscriber.putNext(.done(value))
            } else {
                subscriber.putNext(.progress)
            }
        })
        
        return ActionDisposable {
            fetched.dispose()
            data.dispose()
        }
    }
}

private enum ExternalShareItemsState {
    case progress
    case done([ExternalShareItem])
}

private struct CollectableExternalShareItem {
    let url: String?
    let text: String
    let mediaReference: AnyMediaReference?
}

private func collectExternalShareItems(strings: PresentationStrings, postbox: Postbox, collectableItems: [CollectableExternalShareItem]) -> Signal<ExternalShareItemsState, NoError> {
    var signals: [Signal<ExternalShareItemStatus, NoError>] = []
    for item in collectableItems {
        if let mediaReference = item.mediaReference, let file = mediaReference.media as? TelegramMediaFile {
            signals.append(collectExternalShareResource(postbox: postbox, resourceReference: mediaReference.resourceReference(file.resource), statsCategory: statsCategoryForFileWithAttributes(file.attributes))
                |> mapToSignal { next -> Signal<ExternalShareItemStatus, NoError> in
                    switch next {
                        case .progress:
                            return .single(.progress)
                        case let .done(data):
                            if file.isSticker, let dimensions = file.dimensions {
                                return chatMessageSticker(postbox: postbox, file: file, small: false, fetched: true, onlyFullSize: true)
                                |> map { f -> ExternalShareItemStatus in
                                    let context = f(TransformImageArguments(corners: ImageCorners(), imageSize: dimensions, boundingSize: dimensions, intrinsicInsets: UIEdgeInsets(), emptyColor: nil, scale: 1.0))
                                    if let image = context?.generateImage() {
                                        return .done(.image(image))
                                    } else {
                                        return .progress
                                    }
                                }
                            } else {
                                let fileName: String
                                if let value = file.fileName {
                                    fileName = value
                                } else if file.isVideo {
                                    fileName = "telegram_video.mp4"
                                } else {
                                    fileName = "file"
                                }
                                let randomDirectory = UUID()
                                let safeFileName = fileName.replacingOccurrences(of: "/", with: "_")
                                let fileDirectory = NSTemporaryDirectory() + "\(randomDirectory)"
                                let _ = try? FileManager.default.createDirectory(at: URL(fileURLWithPath: fileDirectory), withIntermediateDirectories: true, attributes: nil)
                                let filePath = fileDirectory + "/\(safeFileName)"
                                if let _ = try? FileManager.default.copyItem(at: URL(fileURLWithPath: data.path), to: URL(fileURLWithPath: filePath)) {
                                    return .single(.done(.file(URL(fileURLWithPath: filePath), fileName, file.mimeType)))
                                } else {
                                    return .single(.progress)
                                }
                            }
                    }
            })
        } else if let mediaReference = item.mediaReference, let image = mediaReference.media as? TelegramMediaImage, let largest = largestImageRepresentation(image.representations) {
            signals.append(collectExternalShareResource(postbox: postbox, resourceReference: mediaReference.resourceReference(largest.resource), statsCategory: .image)
            |> map { next -> ExternalShareItemStatus in
                switch next {
                    case .progress:
                        return .progress
                    case let .done(data):
                        if let fileData = try? Data(contentsOf: URL(fileURLWithPath: data.path)), let image = UIImage(data: fileData) {
                            return .done(.image(image))
                        } else {
                            return .progress
                        }
                }
            })
        } else if let mediaReference = item.mediaReference, let poll = mediaReference.media as? TelegramMediaPoll {
            var text = "📊 \(poll.text)"
            text.append("\n\(strings.MessagePoll_LabelAnonymous)")
            for option in poll.options {
                text.append("\n— \(option.text)")
            }
            let totalVoters = poll.results.totalVoters ?? 0
            if totalVoters == 0 {
                text.append("\n\(strings.MessagePoll_NoVotes)")
            } else {
                text.append("\n\(strings.MessagePoll_VotedCount(totalVoters))")
            }
            signals.append(.single(.done(.text(text))))
        }
        if let url = item.url, let parsedUrl = URL(string: url) {
            if signals.isEmpty {
                signals.append(.single(.done(.url(parsedUrl))))
            }
        }
        if !item.text.isEmpty {
            if signals.isEmpty {
                signals.append(.single(.done(.text(item.text))))
            }
        }
    }
    return combineLatest(signals)
    |> map { statuses -> ExternalShareItemsState in
        var items: [ExternalShareItem] = []
        for status in statuses {
            switch status {
                case .progress:
                    return .progress
                case let .done(item):
                    items.append(item)
            }
        }
        return .done(items)
    }
    |> distinctUntilChanged(isEqual: { lhs, rhs in
        if case .progress = lhs, case .progress = rhs {
            return true
        } else {
            return false
        }
    })
}

public final class ShareController: ViewController {
    private var controllerNode: ShareControllerNode {
        return self.displayNode as! ShareControllerNode
    }
    
    private var animatedIn = false
    
    private let sharedContext: SharedAccountContext
    private let currentContext: AccountContext
    private var currentAccount: Account
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?
    
    private let externalShare: Bool
    private let immediateExternalShare: Bool
    private let subject: ShareControllerSubject
    private let switchableAccounts: [AccountWithInfo]
    
    private let peers = Promise<([RenderedPeer], Peer)>()
    private let peersDisposable = MetaDisposable()
    private let readyDisposable = MetaDisposable()
    private let acountActiveDisposable = MetaDisposable()
    
    private var defaultAction: ShareControllerAction?
    
    public var dismissed: ((Bool) -> Void)?
    
    public convenience init(context: AccountContext, subject: ShareControllerSubject, preferredAction: ShareControllerPreferredAction = .default, showInChat: ((Message) -> Void)? = nil, externalShare: Bool = true, immediateExternalShare: Bool = false, switchableAccounts: [AccountWithInfo] = []) {
        self.init(sharedContext: context.sharedContext, currentContext: context, subject: subject, preferredAction: preferredAction, showInChat: showInChat, externalShare: externalShare, immediateExternalShare: immediateExternalShare, switchableAccounts: switchableAccounts)
    }
    
    public init(sharedContext: SharedAccountContext, currentContext: AccountContext, subject: ShareControllerSubject, preferredAction: ShareControllerPreferredAction = .default, showInChat: ((Message) -> Void)? = nil, externalShare: Bool = true, immediateExternalShare: Bool = false, switchableAccounts: [AccountWithInfo] = []) {
        self.sharedContext = sharedContext
        self.currentContext = currentContext
        self.currentAccount = currentContext.account
        self.subject = subject
        self.externalShare = externalShare
        self.immediateExternalShare = immediateExternalShare
        self.switchableAccounts = switchableAccounts
        
        self.presentationData = self.sharedContext.currentPresentationData.with { $0 }
        
        super.init(navigationBarPresentationData: nil)
        
        switch subject {
            case let .url(text):
                self.defaultAction = ShareControllerAction(title: self.presentationData.strings.ShareMenu_CopyShareLink, action: { [weak self] in
                    UIPasteboard.general.string = text
                    self?.controllerNode.cancel?()
                })
            case .text:
                break
            case let .mapMedia(media):
                self.defaultAction = ShareControllerAction(title: self.presentationData.strings.ShareMenu_CopyShareLink, action: { [weak self] in
                    let latLong = "\(media.latitude),\(media.longitude)"
                    let url = "https://maps.apple.com/maps?ll=\(latLong)&q=\(latLong)&t=m"
                    UIPasteboard.general.string = url
                    self?.controllerNode.cancel?()
                })
                break
            case .quote:
                break
            case let .image(representations):
                if case .saveToCameraRoll = preferredAction {
                    self.defaultAction = ShareControllerAction(title: self.presentationData.strings.Preview_SaveToCameraRoll, action: { [weak self] in
                        self?.saveToCameraRoll(representations: representations)
                    })
                }
            case let .media(mediaReference):
                var canSave = false
                if mediaReference.media is TelegramMediaImage {
                    canSave = true
                } else if mediaReference.media is TelegramMediaFile {
                    canSave = true
                }
                if case .saveToCameraRoll = preferredAction, canSave {
                    self.defaultAction = ShareControllerAction(title: self.presentationData.strings.Preview_SaveToCameraRoll, action: { [weak self] in
                        self?.saveToCameraRoll(mediaReference: mediaReference)
                    })
                }
            case let .messages(messages):
                if case .saveToCameraRoll = preferredAction {
                    self.defaultAction = ShareControllerAction(title: self.presentationData.strings.Preview_SaveToCameraRoll, action: { [weak self] in
                        self?.saveToCameraRoll(messages: messages)
                    })
                } else if let message = messages.first {
                    let groupingKey: Int64? = message.groupingKey
                    var sameGroupingKey = groupingKey != nil
                    if sameGroupingKey {
                        for message in messages {
                            if message.groupingKey != groupingKey {
                                sameGroupingKey = false
                                break
                            }
                        }
                    }
                    if let showInChat = showInChat, messages.count == 1 {
                        self.defaultAction = ShareControllerAction(title: self.presentationData.strings.SharedMedia_ViewInChat, action: { [weak self] in
                            self?.controllerNode.cancel?()
                            showInChat(message)
                        })
                    }
                    else if let chatPeer = message.peers[message.id.peerId] as? TelegramChannel, messages.count == 1 || sameGroupingKey {
                        if message.id.namespace == Namespaces.Message.Cloud, let addressName = chatPeer.addressName, !addressName.isEmpty {
                            self.defaultAction = ShareControllerAction(title: self.presentationData.strings.ShareMenu_CopyShareLink, action: { [weak self] in
                                guard let strongSelf = self else {
                                    return
                                }
                                let _ = (exportMessageLink(account: strongSelf.currentAccount, peerId: chatPeer.id, messageId: message.id)
                                |> map { result -> String in
                                    return result ?? "https://t.me/\(addressName)/\(message.id.id)"
                                }
                                |> deliverOnMainQueue).start(next: { link in
                                    UIPasteboard.general.string = link
                                })
                                strongSelf.controllerNode.cancel?()
                            })
                        }
                    }
                }
            case .fromExternal:
                break
        }
        
        if case let .custom(action) = preferredAction {
            self.defaultAction = ShareControllerAction(title: action.title, action: { [weak self] in
                self?.controllerNode.cancel?()
                action.action()
            })
        }
        
        self.presentationDataDisposable = (self.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            if let strongSelf = self, strongSelf.isNodeLoaded {
                strongSelf.controllerNode.updatePresentationData(presentationData)
            }
        })
        
        self.switchToAccount(account: currentAccount, animateIn: false)
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.peersDisposable.dispose()
        self.readyDisposable.dispose()
        self.acountActiveDisposable.dispose()
    }
    
    override public func loadDisplayNode() {
        self.displayNode = ShareControllerNode(sharedContext: self.sharedContext, defaultAction: self.defaultAction, requestLayout: { [weak self] transition in
            self?.requestLayout(transition: transition)
        }, externalShare: self.externalShare, immediateExternalShare: self.immediateExternalShare)
        self.controllerNode.dismiss = { [weak self] shared in
            self?.presentingViewController?.dismiss(animated: false, completion: nil)
            self?.dismissed?(shared)
        }
        self.controllerNode.cancel = { [weak self] in
            self?.controllerNode.view.endEditing(true)
            self?.controllerNode.animateOut(shared: false, completion: {
                self?.presentingViewController?.dismiss(animated: false, completion: nil)
                self?.dismissed?(false)
            })
        }
        self.controllerNode.share = { [weak self] text, peerIds in
            if let strongSelf = self {
                switch strongSelf.subject {
                    case let .url(url):
                        for peerId in peerIds {
                            var messages: [EnqueueMessage] = []
                            if !text.isEmpty {
                                messages.append(.message(text: text, attributes: [], mediaReference: nil, replyToMessageId: nil, localGroupingKey: nil))
                            }
                            messages.append(.message(text: url, attributes: [], mediaReference: nil, replyToMessageId: nil, localGroupingKey: nil))
                            let _ = enqueueMessages(account: strongSelf.currentAccount, peerId: peerId, messages: messages).start()
                        }
                        return .complete()
                    case let .text(string):
                        for peerId in peerIds {
                            var messages: [EnqueueMessage] = []
                            if !text.isEmpty {
                                messages.append(.message(text: text, attributes: [], mediaReference: nil, replyToMessageId: nil, localGroupingKey: nil))
                            }
                            messages.append(.message(text: string, attributes: [], mediaReference: nil, replyToMessageId: nil, localGroupingKey: nil))
                            let _ = enqueueMessages(account: strongSelf.currentAccount, peerId: peerId, messages: messages).start()
                        }
                        return .complete()
                    case let .quote(string, url):
                        for peerId in peerIds {
                            var messages: [EnqueueMessage] = []
                            if !text.isEmpty {
                                messages.append(.message(text: text, attributes: [], mediaReference: nil, replyToMessageId: nil, localGroupingKey: nil))
                            }
                            let attributedText = NSMutableAttributedString(string: string, attributes: [ChatTextInputAttributes.italic: true as NSNumber])
                            attributedText.append(NSAttributedString(string: "\n\n\(url)"))
                            let entities = generateChatInputTextEntities(attributedText)
                            messages.append(.message(text: attributedText.string, attributes: [TextEntitiesMessageAttribute(entities: entities)], mediaReference: nil, replyToMessageId: nil, localGroupingKey: nil))
                            let _ = enqueueMessages(account: strongSelf.currentAccount, peerId: peerId, messages: messages).start()
                        }
                        return .complete()
                    case let .image(representations):
                        for peerId in peerIds {
                            var messages: [EnqueueMessage] = []
                            if !text.isEmpty {
                                messages.append(.message(text: text, attributes: [], mediaReference: nil, replyToMessageId: nil, localGroupingKey: nil))
                            }
                            messages.append(.message(text: "", attributes: [], mediaReference: .standalone(media: TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.LocalImage, id: arc4random64()), representations: representations.map({ $0.representation }), immediateThumbnailData: nil, reference: nil, partialReference: nil)), replyToMessageId: nil, localGroupingKey: nil))
                            let _ = enqueueMessages(account: strongSelf.currentAccount, peerId: peerId, messages: messages).start()
                        }
                        return .complete()
                    case let .media(mediaReference):
                        for peerId in peerIds {
                            var messages: [EnqueueMessage] = []
                            if !text.isEmpty {
                                messages.append(.message(text: text, attributes: [], mediaReference: nil, replyToMessageId: nil, localGroupingKey: nil))
                            }
                            messages.append(.message(text: "", attributes: [], mediaReference: mediaReference, replyToMessageId: nil, localGroupingKey: nil))
                            let _ = enqueueMessages(account: strongSelf.currentAccount, peerId: peerId, messages: messages).start()
                        }
                        return .complete()
                    case let .mapMedia(media):
                        for peerId in peerIds {
                            var messages: [EnqueueMessage] = []
                            if !text.isEmpty {
                                messages.append(.message(text: text, attributes: [], mediaReference: nil, replyToMessageId: nil, localGroupingKey: nil))
                            }
                            messages.append(.message(text: "", attributes: [], mediaReference: .standalone(media: media), replyToMessageId: nil, localGroupingKey: nil))
                            let _ = enqueueMessages(account: strongSelf.currentAccount, peerId: peerId, messages: messages).start()
                        }
                        return .complete()
                    case let .messages(messages):
                        for peerId in peerIds {
                            var messagesToEnqueue: [EnqueueMessage] = []
                            if !text.isEmpty {
                                messagesToEnqueue.append(.message(text: text, attributes: [], mediaReference: nil, replyToMessageId: nil, localGroupingKey: nil))
                            }
                            for message in messages {
                                messagesToEnqueue.append(.forward(source: message.id, grouping: .auto))
                            }
                            let _ = enqueueMessages(account: strongSelf.currentAccount, peerId: peerId, messages: messagesToEnqueue).start()
                        }
                        return .single(.done)
                    case let .fromExternal(f):
                        return f(peerIds, text, strongSelf.currentAccount)
                        |> map { state -> ShareState in
                            switch state {
                                case .preparing:
                                    return .preparing
                                case let .progress(value):
                                    return .progress(value)
                                case .done:
                                    return .done
                            }
                        }
                }
            }
            return .complete()
        }
        self.controllerNode.shareExternal = { [weak self] in
            if let strongSelf = self {
                var collectableItems: [CollectableExternalShareItem] = []
                switch strongSelf.subject {
                    case let .url(text):
                        collectableItems.append(CollectableExternalShareItem(url: text, text: "", mediaReference: nil))
                    case let .text(string):
                        collectableItems.append(CollectableExternalShareItem(url: "", text: string, mediaReference: nil))
                    case let .quote(text, url):
                        collectableItems.append(CollectableExternalShareItem(url: "", text: "\"\(text)\"\n\n\(url)", mediaReference: nil))
                    case let .image(representations):
                        let media = TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.LocalImage, id: arc4random64()), representations: representations.map({ $0.representation }), immediateThumbnailData: nil, reference: nil, partialReference: nil)
                        collectableItems.append(CollectableExternalShareItem(url: "", text: "", mediaReference: .standalone(media: media)))
                    case let .media(mediaReference):
                        collectableItems.append(CollectableExternalShareItem(url: "", text: "", mediaReference: mediaReference))
                    case let .mapMedia(media):
                        let latLong = "\(media.latitude),\(media.longitude)"
                        collectableItems.append(CollectableExternalShareItem(url: "https://maps.apple.com/maps?ll=\(latLong)&q=\(latLong)&t=m", text: "", mediaReference: nil))
                    case let .messages(messages):
                        for message in messages {
                            var url: String?
                            var selectedMedia: Media?
                            loop: for media in message.media {
                                switch media {
                                    case _ as TelegramMediaImage, _ as TelegramMediaFile:
                                        selectedMedia = media
                                        break loop
                                    case let webpage as TelegramMediaWebpage:
                                        if case let .Loaded(content) = webpage.content {
                                            if let file = content.file {
                                                selectedMedia = file
                                            } else if let image = content.image {
                                                selectedMedia = image
                                            }
                                        }
                                    case _ as TelegramMediaPoll:
                                        selectedMedia = media
                                        break loop
                                    default:
                                        break
                                }
                            }
                            if let chatPeer = message.peers[message.id.peerId] as? TelegramChannel {
                                if message.id.namespace == Namespaces.Message.Cloud, let addressName = chatPeer.addressName, !addressName.isEmpty {
                                    url = "https://t.me/\(addressName)/\(message.id.id)"
                                }
                            }
                            collectableItems.append(CollectableExternalShareItem(url: url, text: message.text, mediaReference: selectedMedia.flatMap({ AnyMediaReference.message(message: MessageReference(message), media: $0) })))
                        }
                    case .fromExternal:
                        break
                }
                return (collectExternalShareItems(strings: strongSelf.presentationData.strings, postbox: strongSelf.currentAccount.postbox, collectableItems: collectableItems)
                |> deliverOnMainQueue)
                |> map { state in
                    switch state {
                        case .progress:
                            return .preparing
                        case let .done(items):
                            if let strongSelf = self, !items.isEmpty {
                                strongSelf.ready.set(.single(true))
                                var activityItems: [Any] = []
                                for item in items {
                                    switch item {
                                        case let .url(url):
                                            activityItems.append(url as NSURL)
                                        case let .text(text):
                                            activityItems.append(text as NSString)
                                        case let .image(image):
                                            activityItems.append(image)
                                        case let .file(url, _, _):
                                            activityItems.append(url)
                                    }
                                }
                                let activityController = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
                                
                                if let window = strongSelf.view.window, let rootViewController = window.rootViewController {
                                    activityController.popoverPresentationController?.sourceView = window
                                    activityController.popoverPresentationController?.sourceRect = CGRect(origin: CGPoint(x: window.bounds.width / 2.0, y: window.bounds.size.height - 1.0), size: CGSize(width: 1.0, height: 1.0))
                                    rootViewController.present(activityController, animated: true, completion: nil)
                                }
                            }
                            return .done
                    }
                }
            } else {
                return .single(.done)
            }
        }
        self.controllerNode.switchToAnotherAccount = { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.controllerNode.animateOut(shared: false, completion: {})
            
            let presentationData = strongSelf.sharedContext.currentPresentationData.with { $0 }
            let controller = ActionSheetController(presentationTheme: presentationData.theme)
            controller.dismissed = { [weak self] cancelled in
                if cancelled {
                    self?.controllerNode.animateIn()
                }
            }
            let dismissAction: () -> Void = { [weak controller] in
                controller?.dismissAnimated()
            }
            var items: [ActionSheetItem] = []
            for info in strongSelf.switchableAccounts {
                items.append(ActionSheetPeerItem(account: info.account, peer: info.peer, title: info.peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder), isSelected: info.account.id == strongSelf.currentAccount.id, strings: presentationData.strings, theme: presentationData.theme, action: { [weak self] in
                    dismissAction()
                    self?.switchToAccount(account: info.account, animateIn: true)
                }))
            }
            controller.setItemGroups([
                ActionSheetItemGroup(items: items)
            ])
            strongSelf.view.endEditing(true)
            strongSelf.present(controller, in: .window(.root), with: ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
        }
        self.displayNodeDidLoad()
        self.peersDisposable.set((self.peers.get()
        |> deliverOnMainQueue).start(next: { [weak self] next in
            if let strongSelf = self {
                strongSelf.controllerNode.updatePeers(account: strongSelf.currentAccount, switchableAccounts: strongSelf.switchableAccounts, peers: next.0, accountPeer: next.1, defaultAction: strongSelf.defaultAction)
            }
        }))
        self.ready.set(self.controllerNode.ready.get())
    }
    
    override public func loadView() {
        super.loadView()
        
        self.statusBar.removeFromSupernode()
    }
    
    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if !self.animatedIn {
            self.animatedIn = true
            self.controllerNode.animateIn()
        }
    }
    
    override public func dismiss(completion: (() -> Void)? = nil) {
        self.controllerNode.view.endEditing(true)
        self.controllerNode.animateOut(shared: false, completion: { [weak self] in
            self?.presentingViewController?.dismiss(animated: false, completion: nil)
            completion?()
        })
    }
    
    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        
        self.controllerNode.containerLayoutUpdated(layout, navigationBarHeight: self.navigationHeight, transition: transition)
    }
    
    private func saveToCameraRoll(messages: [Message]) {
        let postbox = self.currentAccount.postbox
        let signals: [Signal<Float, NoError>] = messages.compactMap { message -> Signal<Float, NoError>? in
            if let media = message.media.first {
                let context: AccountContext
                if self.currentContext.account.id == self.currentAccount.id {
                    context = self.currentContext
                } else {
                    context = AccountContext(sharedContext: self.sharedContext, account: self.currentAccount, limitsConfiguration: .defaultValue)
                }
                return TelegramUI.saveToCameraRoll(context: context, postbox: postbox, mediaReference: .message(message: MessageReference(message), media: media))
            } else {
                return nil
            }
        }
        if !signals.isEmpty {
            let total = combineLatest(signals)
            |> map { values -> Float? in
                var total: Float = 0.0
                for value in values {
                    total += value
                }
                total /= Float(values.count)
                return total
            }
            self.controllerNode.transitionToProgressWithValue(signal: total)
        }
    }
    
    private func saveToCameraRoll(representations: [ImageRepresentationWithReference]) {
        let media = TelegramMediaImage(imageId: MediaId(namespace: 0, id: 0), representations: representations.map({ $0.representation }), immediateThumbnailData: nil, reference: nil, partialReference: nil)
        let context: AccountContext
        if self.currentContext.account.id == self.currentAccount.id {
            context = self.currentContext
        } else {
            context = AccountContext(sharedContext: self.sharedContext, account: self.currentAccount, limitsConfiguration: .defaultValue)
        }
        self.controllerNode.transitionToProgressWithValue(signal: TelegramUI.saveToCameraRoll(context: context, postbox: context.account.postbox, mediaReference: .standalone(media: media)) |> map(Optional.init))
    }
    
    private func saveToCameraRoll(mediaReference: AnyMediaReference) {
        let context: AccountContext
        if self.currentContext.account.id == self.currentAccount.id {
            context = self.currentContext
        } else {
            context = AccountContext(sharedContext: self.sharedContext, account: self.currentAccount, limitsConfiguration: .defaultValue)
        }
        self.controllerNode.transitionToProgressWithValue(signal: TelegramUI.saveToCameraRoll(context: context, postbox: context.account.postbox, mediaReference: mediaReference) |> map(Optional.init))
    }
    
    private func switchToAccount(account: Account, animateIn: Bool) {
        self.currentAccount = account
        self.acountActiveDisposable.set(self.sharedContext.setAccountUserInterfaceInUse(account.id))
        
        self.peers.set(combineLatest(self.currentAccount.postbox.loadedPeerWithId(self.currentAccount.peerId) |> take(1), self.currentAccount.viewTracker.tailChatListView(groupId: nil, count: 150) |> take(1))
        |> map { accountPeer, view -> ([RenderedPeer], Peer) in
            var peers: [RenderedPeer] = []
            for entry in view.0.entries.reversed() {
                switch entry {
                case let .MessageEntry(_, _, _, _, _, renderedPeer, _):
                    if let peer = renderedPeer.peers[renderedPeer.peerId], peer.id != accountPeer.id, canSendMessagesToPeer(peer) {
                        peers.append(renderedPeer)
                    }
                default:
                    break
                }
            }
            return (peers, accountPeer)
        })
        self.peersDisposable.set((self.peers.get()
        |> deliverOnMainQueue).start(next: { [weak self] next in
            if let strongSelf = self {
                strongSelf.controllerNode.updatePeers(account: strongSelf.currentAccount, switchableAccounts: strongSelf.switchableAccounts, peers: next.0, accountPeer: next.1, defaultAction: strongSelf.defaultAction)
                
                if animateIn {
                    strongSelf.readyDisposable.set((strongSelf.controllerNode.ready.get()
                    |> filter({ $0 })
                    |> take(1)
                    |> deliverOnMainQueue).start(next: { [weak self] _ in
                        guard let strongSelf = self else {
                            return
                        }
                        strongSelf.controllerNode.animateIn()
                    }))
                }
            }
        }))
    }
}
