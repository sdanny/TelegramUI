import Foundation
import UIKit
import LegacyComponents
import Display
import SwiftSignalKit
import Postbox
import TelegramCore

func legacyAttachmentMenu(context: AccountContext, peer: Peer, editMediaOptions: MessageMediaEditingOptions?, saveEditedPhotos: Bool, allowGrouping: Bool, theme: PresentationTheme, strings: PresentationStrings, parentController: LegacyController, recentlyUsedInlineBots: [Peer], openGallery: @escaping () -> Void, openCamera: @escaping (TGAttachmentCameraView?, TGMenuSheetController?) -> Void, openFileGallery: @escaping () -> Void, openWebSearch: @escaping () -> Void, openMap: @escaping () -> Void, openContacts: @escaping () -> Void, openPoll: @escaping () -> Void, sendMessagesWithSignals: @escaping ([Any]?) -> Void, selectRecentlyUsedInlineBot: @escaping (Peer) -> Void) -> TGMenuSheetController {
    let isSecretChat = peer.id.namespace == Namespaces.Peer.SecretChat
    
    let controller = TGMenuSheetController(context: parentController.context, dark: false)!
    controller.dismissesByOutsideTap = true
    controller.hasSwipeGesture = true
    controller.maxHeight = 445.0
    controller.forceFullScreen = true
    
    var itemViews: [Any] = []
    
    var editing = false
    var canSendImageOrVideo = false
    var canEditCurrent = false
    if let editMediaOptions = editMediaOptions, editMediaOptions.contains(.imageOrVideo) {
        canSendImageOrVideo = true
        editing = true
        canEditCurrent = true
    } else {
        canSendImageOrVideo = true
    }
    
    var carouselItemView: TGAttachmentCarouselItemView?
    
    var underlyingViews: [UIView] = []
    
    if canSendImageOrVideo {
        let carouselItem = TGAttachmentCarouselItemView(context: parentController.context, camera: PGCamera.cameraAvailable(), selfPortrait: false, forProfilePhoto: false, assetType: TGMediaAssetAnyType, saveEditedPhotos: !isSecretChat && saveEditedPhotos, allowGrouping: editMediaOptions == nil && allowGrouping, allowSelection: editMediaOptions == nil, allowEditing: true, document: false)!
        carouselItemView = carouselItem
        carouselItem.suggestionContext = legacySuggestionContext(account: context.account, peerId: peer.id)
        carouselItem.recipientName = peer.displayTitle
        carouselItem.cameraPressed = { [weak controller] cameraView in
            if let controller = controller {
                DeviceAccess.authorizeAccess(to: .camera, presentationData: context.sharedContext.currentPresentationData.with { $0 }, present: context.sharedContext.presentGlobalController, openSettings: context.sharedContext.applicationBindings.openSettings, { value in
                    if value {
                        openCamera(cameraView, controller)
                    }
                })
            }
        }
        if (peer is TelegramUser) && peer.id != context.account.peerId {
            carouselItem.hasTimer = true
        }
        carouselItem.sendPressed = { [weak controller, weak carouselItem] currentItem, asFiles in
            if let controller = controller, let carouselItem = carouselItem {
                controller.dismiss(animated: true)
                let intent: TGMediaAssetsControllerIntent = asFiles ? TGMediaAssetsControllerSendFileIntent : TGMediaAssetsControllerSendMediaIntent
                let signals = TGMediaAssetsController.resultSignals(for: carouselItem.selectionContext, editingContext: carouselItem.editingContext, intent: intent, currentItem: currentItem, storeAssets: true, useMediaCache: false, descriptionGenerator: legacyAssetPickerItemGenerator(), saveEditedPhotos: saveEditedPhotos)
                sendMessagesWithSignals(signals)
            }
        };
        carouselItem.allowCaptions = true
        itemViews.append(carouselItem)
        
        let galleryItem = TGMenuSheetButtonItemView(title: editing ? strings.Conversation_EditingMessageMediaChange : strings.AttachmentMenu_PhotoOrVideo, type: TGMenuSheetButtonTypeDefault, action: { [weak controller] in
            controller?.dismiss(animated: true)
            openGallery()
        })!
        if !editing {
            galleryItem.longPressAction = { [weak controller] in
                if let controller = controller {
                    controller.dismiss(animated: true)
                }
                openWebSearch()
            }
        }
        itemViews.append(galleryItem)
        
        underlyingViews.append(galleryItem)
    }
    
    if !editing {
        let fileItem = TGMenuSheetButtonItemView(title: strings.AttachmentMenu_File, type: TGMenuSheetButtonTypeDefault, action: {[weak controller] in
            controller?.dismiss(animated: true)
            openFileGallery()
        })!
        itemViews.append(fileItem)
        underlyingViews.append(fileItem)
    }
    
    if canEditCurrent {
        let fileItem = TGMenuSheetButtonItemView(title: strings.AttachmentMenu_File, type: TGMenuSheetButtonTypeDefault, action: {[weak controller] in
            controller?.dismiss(animated: true)
            openFileGallery()
        })!
        itemViews.append(fileItem)
    }
    
    if editMediaOptions == nil {
        let locationItem = TGMenuSheetButtonItemView(title: strings.Conversation_Location, type: TGMenuSheetButtonTypeDefault, action: { [weak controller] in
            controller?.dismiss(animated: true)
            openMap()
        })!
        itemViews.append(locationItem)
        
        if (peer is TelegramGroup || peer is TelegramChannel) && canSendMessagesToPeer(peer) {
            let pollItem = TGMenuSheetButtonItemView(title: strings.AttachmentMenu_Poll, type: TGMenuSheetButtonTypeDefault, action: { [weak controller] in
                controller?.dismiss(animated: true)
                openPoll()
            })!
            itemViews.append(pollItem)
        }
    
        let contactItem = TGMenuSheetButtonItemView(title: strings.Conversation_Contact, type: TGMenuSheetButtonTypeDefault, action: { [weak controller] in
            controller?.dismiss(animated: true)
            openContacts()
        })!
        itemViews.append(contactItem)
    }
    
    carouselItemView?.underlyingViews = underlyingViews
    
    if editMediaOptions == nil {
        for i in 0 ..< min(20, recentlyUsedInlineBots.count) {
            let peer = recentlyUsedInlineBots[i]
            let addressName = peer.addressName
            if let addressName = addressName {
                let botItem = TGMenuSheetButtonItemView(title: "@" + addressName, type: TGMenuSheetButtonTypeDefault, action: { [weak controller] in
                    controller?.dismiss(animated: true)
                    
                    selectRecentlyUsedInlineBot(peer)
                })!
                botItem.overflow = true
                itemViews.append(botItem)
            }
        }
    }
    
    carouselItemView?.remainingHeight = TGMenuSheetButtonItemViewHeight * CGFloat(itemViews.count - 1)
    
    let cancelItem = TGMenuSheetButtonItemView(title: strings.Common_Cancel, type: TGMenuSheetButtonTypeCancel, action: { [weak controller] in
        controller?.dismiss(animated: true)
    })!
    itemViews.append(cancelItem)
    
    controller.setItemViews(itemViews)
    
    return controller
}

func legacyMenuPaletteFromTheme(_ theme: PresentationTheme) -> TGMenuSheetPallete {
    let sheetTheme = theme.actionSheet
    return TGMenuSheetPallete(dark: theme.overallDarkAppearance, backgroundColor: sheetTheme.opaqueItemBackgroundColor, selectionColor: sheetTheme.opaqueItemHighlightedBackgroundColor, separatorColor: sheetTheme.opaqueItemSeparatorColor, accentColor: sheetTheme.controlAccentColor, destructiveColor: sheetTheme.destructiveActionTextColor, textColor: sheetTheme.primaryTextColor, secondaryTextColor: sheetTheme.secondaryTextColor, spinnerColor: sheetTheme.secondaryTextColor, badgeTextColor: sheetTheme.controlAccentColor, badgeImage: nil, cornersImage: generateStretchableFilledCircleImage(diameter: 11.0, color: nil, strokeColor: nil, strokeWidth: nil, backgroundColor: sheetTheme.opaqueItemBackgroundColor))
}

func presentLegacyPasteMenu(context: AccountContext, peer: Peer, saveEditedPhotos: Bool, allowGrouping: Bool, theme: PresentationTheme, strings: PresentationStrings, images: [UIImage], sendMessagesWithSignals: @escaping ([Any]?) -> Void, present: (ViewController, Any?) -> Void, initialLayout: ContainerViewLayout? = nil) -> ViewController {
    let legacyController = LegacyController(presentation: .custom, theme: theme, initialLayout: initialLayout)
    legacyController.statusBar.statusBarStyle = .Ignore
    legacyController.controllerLoaded = { [weak legacyController] in
        legacyController?.view.disablesInteractiveTransitionGestureRecognizer = true
    }
    
    let emptyController = LegacyEmptyController(context: legacyController.context)!
    let navigationController = makeLegacyNavigationController(rootController: emptyController)
    navigationController.setNavigationBarHidden(true, animated: false)
    legacyController.bind(controller: navigationController)
    
    var hasTimer = false
    if (peer is TelegramUser) && peer.id != context.account.peerId {
        hasTimer = true
    }
    let recipientName = peer.displayTitle
    
    legacyController.enableSizeClassSignal = true

    let controller = TGClipboardMenu.present(inParentController: emptyController, context: legacyController.context, images: images, hasCaption: true, hasTimer: hasTimer, recipientName: recipientName, completed: { selectionContext, editingContext, currentItem in
        let signals = TGClipboardMenu.resultSignals(for: selectionContext, editingContext: editingContext, currentItem: currentItem, descriptionGenerator: legacyAssetPickerItemGenerator())
        sendMessagesWithSignals(signals)
    }, dismissed: { [weak legacyController] in
        legacyController?.dismiss()
    }, sourceView: emptyController.view, sourceRect: nil)!
    controller.customRemoveFromParentViewController = { [weak legacyController] in
        legacyController?.dismiss()
    }
    
    let presentationDisposable = context.sharedContext.presentationData.start(next: { [weak legacyController] presentationData in
        if let legacyController = legacyController, let controller = legacyController.legacyController as? TGMenuSheetController  {
            controller.pallete = legacyMenuPaletteFromTheme(presentationData.theme)
        }
    })
    legacyController.disposables.add(presentationDisposable)
    
    present(legacyController, nil)
    controller.present(in: emptyController, sourceView: nil, animated: true)
    
    return legacyController
}
