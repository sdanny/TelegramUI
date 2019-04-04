import Foundation
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore

func presentContactsWarningSuppression(context: AccountContext, present: (ViewController, Any?) -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    present(textAlertController(context: context, title: presentationData.strings.Contacts_PermissionsSuppressWarningTitle, text: presentationData.strings.Contacts_PermissionsSuppressWarningText, actions: [TextAlertAction(type: .genericAction, title: presentationData.strings.Contacts_PermissionsKeepDisabled, action: {
        ApplicationSpecificNotice.setContactsPermissionWarning(accountManager: context.sharedContext.accountManager, value: Int32(Date().timeIntervalSince1970))
    }), TextAlertAction(type: .defaultAction, title: presentationData.strings.Contacts_PermissionsEnable, action: {
        let _ = (DeviceAccess.authorizationStatus(context: context, subject: .contacts)
        |> take(1)
        |> deliverOnMainQueue).start(next: { status in
            switch status {
                case .notDetermined:
                    DeviceAccess.authorizeAccess(to: .contacts, context: context)
                case .denied, .restricted:
                    context.sharedContext.applicationBindings.openSettings()
                default:
                    break
            }
        })
    })]), nil)
}
