import Foundation
import Display
import LegacyComponents
import TelegramCore
import Postbox
import SwiftSignalKit

private func generateClearIcon(color: UIColor) -> UIImage? {
    return generateTintedImage(image: UIImage(bundleImageName: "Components/Search Bar/Clear"), color: color)
}

func legacyLocationPickerController(context: AccountContext, selfPeer: Peer, peer: Peer, sendLocation: @escaping (CLLocationCoordinate2D, MapVenue?) -> Void, sendLiveLocation: @escaping (CLLocationCoordinate2D, Int32) -> Void, theme: PresentationTheme) -> ViewController {
    let legacyController = LegacyController(presentation: .modal(animateIn: true), theme: theme)
    let controller = TGLocationPickerController(context: legacyController.context, intent: TGLocationPickerControllerDefaultIntent)!
    controller.peer = makeLegacyPeer(selfPeer)
    controller.receivingPeer = makeLegacyPeer(peer)
    controller.pallete = legacyLocationPalette(from: theme)
    let namespacesWithEnabledLiveLocation: Set<PeerId.Namespace> = Set([
        Namespaces.Peer.CloudChannel,
        Namespaces.Peer.CloudGroup,
        Namespaces.Peer.CloudUser
    ])
    if namespacesWithEnabledLiveLocation.contains(peer.id.namespace) {
        controller.allowLiveLocationSharing = true
    }
    let navigationController = TGNavigationController(controllers: [controller])!
    controller.navigation_setDismiss({ [weak legacyController] in
        legacyController?.dismiss()
    }, rootController: nil)
    legacyController.bind(controller: navigationController)
    legacyController.supportedOrientations = ViewControllerSupportedOrientations(regularSize: .all, compactSize: .portrait)
    controller.locationPicked = { [weak legacyController] coordinate, venue in
        sendLocation(coordinate, venue.flatMap { venue in
            return MapVenue(title: venue.title, address: venue.address, provider: venue.provider, id: venue.venueId, type: venue.type)
        })
        legacyController?.dismiss()
    }
    controller.liveLocationStarted = { [weak legacyController] coordinate, period in
        sendLiveLocation(coordinate, period)
        legacyController?.dismiss()
    }
    controller.nearbyPlacesSignal = { query, location in
        return SSignal(generator: { subscriber in
            let nearbyPlacesSignal: Signal<[TGLocationVenue], NoError> = resolvePeerByName(account: context.account, name: "foursquare")
            |> take(1)
            |> mapToSignal { peerId -> Signal<ChatContextResultCollection?, NoError> in
                guard let peerId = peerId else {
                    return .single(nil)
                }
                return requestChatContextResults(account: context.account, botId: peerId, peerId: selfPeer.id, query: query ?? "", location: .single((location?.coordinate.latitude ?? 0.0, location?.coordinate.longitude ?? 0.0)), offset: "")
            }
            |> mapToSignal { contextResult -> Signal<[TGLocationVenue], NoError> in
                guard let contextResult = contextResult else {
                    return .single([])
                }
                
                var list: [TGLocationVenue] = []
                for result in contextResult.results {
                    switch result.message {
                        case let .mapLocation(mapMedia, _):
                            let legacyLocation = TGLocationMediaAttachment()
                            legacyLocation.latitude = mapMedia.latitude
                            legacyLocation.longitude = mapMedia.longitude
                            if let venue = mapMedia.venue {
                                legacyLocation.venue = TGVenueAttachment(title: venue.title, address: venue.address, provider: venue.provider, venueId: venue.id, type: venue.type)
                            }
                            list.append(TGLocationVenue(locationAttachment: legacyLocation))
                        default:
                            break
                    }
                }
                
                return .single(list)
            }
            
            let disposable = nearbyPlacesSignal.start(next: { next in
                subscriber?.putNext(next as NSArray)
            }, completed: {
                subscriber?.putCompletion()
            })
            
            return SBlockDisposable(block: {
                disposable.dispose()
            })
        })
    }
    let presentationDisposable = context.sharedContext.presentationData.start(next: { [weak controller] presentationData in
        if let controller = controller  {
            controller.pallete = legacyLocationPalette(from: presentationData.theme)
        }
    })
    legacyController.disposables.add(presentationDisposable)
    return legacyController
}
