import Foundation
import TelegramCore
import Postbox
import SwiftSignalKit

public func freeMediaFileInteractiveFetched(account: Account, fileReference: FileMediaReference) -> Signal<FetchResourceSourceType, FetchResourceError> {
    return fetchedMediaResource(postbox: account.postbox, reference: fileReference.resourceReference(fileReference.media.resource))
}

func freeMediaFileResourceInteractiveFetched(account: Account, fileReference: FileMediaReference, resource: MediaResource) -> Signal<FetchResourceSourceType, FetchResourceError> {
    return fetchedMediaResource(postbox: account.postbox, reference: fileReference.resourceReference(resource))
}

func cancelFreeMediaFileInteractiveFetch(account: Account, file: TelegramMediaFile) {
    account.postbox.mediaBox.cancelInteractiveResourceFetch(file.resource)
}

private func fetchCategoryForFile(_ file: TelegramMediaFile) -> FetchManagerCategory {
    if file.isVoice || file.isInstantVideo {
        return .voice
    } else if file.isAnimated {
        return .animation
    } else {
        return .file
    }
}

public func messageMediaFileInteractiveFetched(context: AccountContext, message: Message, file: TelegramMediaFile, userInitiated: Bool) -> Signal<Void, NoError> {
    return messageMediaFileInteractiveFetched(fetchManager: context.fetchManager, messageId: message.id, messageReference: MessageReference(message), file: file, userInitiated: userInitiated, priority: .userInitiated)
}

func messageMediaFileInteractiveFetched(fetchManager: FetchManager, messageId: MessageId, messageReference: MessageReference, file: TelegramMediaFile, ranges: IndexSet = IndexSet(integersIn: 0 ..< Int(Int32.max) as Range<Int>), userInitiated: Bool, priority: FetchManagerPriority) -> Signal<Void, NoError> {
    let mediaReference = AnyMediaReference.message(message: messageReference, media: file)
    return fetchManager.interactivelyFetched(category: fetchCategoryForFile(file), location: .chat(messageId.peerId), locationKey: .messageId(messageId), mediaReference: mediaReference, resourceReference: mediaReference.resourceReference(file.resource), ranges: ranges, statsCategory: statsCategoryForFileWithAttributes(file.attributes), elevatedPriority: false, userInitiated: userInitiated, priority: priority)
}

func messageMediaFileCancelInteractiveFetch(context: AccountContext, messageId: MessageId, file: TelegramMediaFile) {
    context.fetchManager.cancelInteractiveFetches(category: fetchCategoryForFile(file), location: .chat(messageId.peerId), locationKey: .messageId(messageId), resource: file.resource)
}

public func messageMediaImageInteractiveFetched(context: AccountContext, message: Message, image: TelegramMediaImage, resource: MediaResource, storeToDownloadsPeerType: MediaAutoDownloadPeerType?) -> Signal<Void, NoError> {
    return messageMediaImageInteractiveFetched(fetchManager: context.fetchManager, messageId: message.id, messageReference: MessageReference(message), image: image, resource: resource, userInitiated: true, priority: .userInitiated, storeToDownloadsPeerType: storeToDownloadsPeerType)
}

func messageMediaImageInteractiveFetched(fetchManager: FetchManager, messageId: MessageId, messageReference: MessageReference, image: TelegramMediaImage, resource: MediaResource, userInitiated: Bool, priority: FetchManagerPriority, storeToDownloadsPeerType: MediaAutoDownloadPeerType?) -> Signal<Void, NoError> {
    let mediaReference = AnyMediaReference.message(message: messageReference, media: image)
    return fetchManager.interactivelyFetched(category: .image, location: .chat(messageId.peerId), locationKey: .messageId(messageId), mediaReference: mediaReference, resourceReference: mediaReference.resourceReference(resource), statsCategory: .image, elevatedPriority: false, userInitiated: userInitiated, priority: priority, storeToDownloadsPeerType: storeToDownloadsPeerType)
}

func messageMediaImageCancelInteractiveFetch(context: AccountContext, messageId: MessageId, image: TelegramMediaImage, resource: MediaResource) {
    context.fetchManager.cancelInteractiveFetches(category: .image, location: .chat(messageId.peerId), locationKey: .messageId(messageId), resource: resource)
}

func messageMediaFileStatus(context: AccountContext, messageId: MessageId, file: TelegramMediaFile) -> Signal<MediaResourceStatus, NoError> {
    return context.fetchManager.fetchStatus(category: fetchCategoryForFile(file), location: .chat(messageId.peerId), locationKey: .messageId(messageId), resource: file.resource)
}
