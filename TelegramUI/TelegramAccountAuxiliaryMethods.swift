import Foundation
import TelegramCore
import Postbox

public let telegramAccountAuxiliaryMethods = AccountAuxiliaryMethods(updatePeerChatInputState: { interfaceState, inputState -> PeerChatInterfaceState? in
    if interfaceState == nil {
        return ChatInterfaceState().withUpdatedSynchronizeableInputState(inputState)
    } else if let interfaceState = interfaceState as? ChatInterfaceState {
        return interfaceState.withUpdatedSynchronizeableInputState(inputState)
    } else {
        return interfaceState
    }
}, fetchResource: { account, resource, ranges, _ in
    if let resource = resource as? VideoLibraryMediaResource {
        return fetchVideoLibraryMediaResource(postbox: account.postbox, resource: resource)
    } else if let resource = resource as? LocalFileVideoMediaResource {
        return fetchLocalFileVideoMediaResource(postbox: account.postbox, resource: resource)
    } else if let resource = resource as? LocalFileGifMediaResource {
        return fetchLocalFileGifMediaResource(resource: resource)
    } else if let photoLibraryResource = resource as? PhotoLibraryMediaResource {
        return fetchPhotoLibraryResource(localIdentifier: photoLibraryResource.localIdentifier)
    } else if let mapSnapshotResource = resource as? MapSnapshotMediaResource {
        return fetchMapSnapshotResource(resource: mapSnapshotResource)
    } else if let resource = resource as? ExternalMusicAlbumArtResource {
        return fetchExternalMusicAlbumArtResource(account: account, resource: resource)
    } else if let resource = resource as? ICloudFileResource {
        return fetchICloudFileResource(resource: resource)
    } else if let resource = resource as? SecureIdLocalImageResource {
        return fetchSecureIdLocalImageResource(postbox: account.postbox, resource: resource)
    } else if let resource = resource as? OpenInAppIconResource {
        return fetchOpenInAppIconResource(resource: resource)
    }
    return nil
}, fetchResourceMediaReferenceHash: { resource in
    if let resource = resource as? VideoLibraryMediaResource {
        return fetchVideoLibraryMediaResourceHash(resource: resource)
    }
    return .single(nil)
}, prepareSecretThumbnailData: { data in
    return prepareSecretThumbnailData(data)
})
