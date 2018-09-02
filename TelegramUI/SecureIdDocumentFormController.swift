import Foundation
import Display
import AsyncDisplayKit
import SwiftSignalKit
import Postbox
import TelegramCore

enum SecureIdDocumentFormRequestedData {
    case identity(details: ParsedRequestedPersonalDetails?, document: SecureIdRequestedIdentityDocument?, selfie: Bool, translations: Bool)
    case address(details: Bool, document: SecureIdRequestedAddressDocument?, translations: Bool)
}

final class SecureIdDocumentFormController: FormController<SecureIdDocumentFormState, SecureIdDocumentFormControllerNodeInitParams, SecureIdDocumentFormControllerNode> {
    private let account: Account
    private var presentationData: PresentationData
    private let updatedValues: ([SecureIdValueWithContext]) -> Void
    
    private let context: SecureIdAccessContext
    private let requestedData: SecureIdDocumentFormRequestedData
    private let primaryLanguageByCountry: [String: String]
    private var values: [SecureIdValueWithContext]
    
    private var doneItem: UIBarButtonItem?
    
    init(account: Account, context: SecureIdAccessContext, requestedData: SecureIdDocumentFormRequestedData, primaryLanguageByCountry: [String: String], values: [SecureIdValueWithContext], updatedValues: @escaping ([SecureIdValueWithContext]) -> Void) {
        self.account = account
        self.presentationData = account.telegramApplicationContext.currentPresentationData.with { $0 }
        self.context = context
        self.requestedData = requestedData
        self.primaryLanguageByCountry = primaryLanguageByCountry
        self.values = values
        self.updatedValues = updatedValues
        
        super.init(initParams: SecureIdDocumentFormControllerNodeInitParams(account: account, context: context), presentationData: self.presentationData)
        
        switch requestedData {
            case let .identity(_, document, _, _):
                if let document = document {
                    switch document {
                        case .passport:
                            self.title = self.presentationData.strings.Passport_Identity_TypePassport
                        case .internalPassport:
                            self.title = self.presentationData.strings.Passport_Identity_TypeInternalPassport
                        case .driversLicense:
                            self.title = self.presentationData.strings.Passport_Identity_TypeDriversLicense
                        case .idCard:
                            self.title = self.presentationData.strings.Passport_Identity_TypeIdentityCard
                    }
                } else {
                    self.title = self.presentationData.strings.Passport_Identity_TypePersonalDetails
                }
            case let .address(_, document, _):
                if let document = document {
                    switch document {
                        case .passportRegistration:
                            self.title = self.presentationData.strings.Passport_Address_TypePassportRegistration
                        case .temporaryRegistration:
                            self.title = self.presentationData.strings.Passport_Address_TypeTemporaryRegistration
                        case .utilityBill:
                            self.title = self.presentationData.strings.Passport_Address_TypeUtilityBill
                        case .bankStatement:
                            self.title = self.presentationData.strings.Passport_Address_TypeBankStatement
                        case .rentalAgreement:
                            self.title = self.presentationData.strings.Passport_Address_TypeRentalAgreement
                    }
                } else {
                    self.title = self.presentationData.strings.Passport_Address_TypeResidentialAddress
                }
        }
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Cancel, style: .plain, target: self, action: #selector(self.cancelPressed))
        
        self.doneItem = UIBarButtonItem(title: self.presentationData.strings.Common_Done, style: .done, target: self, action: #selector(self.donePressed))
        self.navigationItem.rightBarButtonItem = doneItem
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
    }
    
    @objc private func cancelPressed() {
        self.dismiss()
    }
    
    @objc private func donePressed() {
        self.controllerNode.save()
    }
    
    override func displayNodeDidLoad() {
        super.displayNodeDidLoad()
        
        self.controllerNode.actionInputStateUpdated = { [weak self] state in
            if let strongSelf = self {
                switch state {
                    case .inProgress:
                        strongSelf.navigationItem.rightBarButtonItem = UIBarButtonItem(customDisplayNode: ProgressNavigationButtonNode(theme: strongSelf.presentationData.theme))
                    case .saveAvailable, .saveNotAvailable:
                        if strongSelf.navigationItem.rightBarButtonItem !== strongSelf.doneItem {
                            strongSelf.navigationItem.rightBarButtonItem = strongSelf.doneItem
                        }
                        if case .saveAvailable = state {
                            strongSelf.doneItem?.isEnabled = true
                        } else {
                            strongSelf.doneItem?.isEnabled = false
                        }
                }
            }
        }
        
        self.controllerNode.completedWithValues = { [weak self] values in
            if let strongSelf = self {
                strongSelf.updatedValues(values ?? [])
                strongSelf.dismiss()
            }
        }
        
        self.controllerNode.dismiss = { [weak self] in
            self?.dismiss()
        }
        
        var values: [SecureIdValueKey: SecureIdValueWithContext] = [:]
        for value in self.values {
            values[value.value.key] = value
        }
        self.controllerNode.updateInnerState(transition: .immediate, with: SecureIdDocumentFormState(requestedData: self.requestedData, values: values, primaryLanguageByCountry: self.primaryLanguageByCountry))
    }
}