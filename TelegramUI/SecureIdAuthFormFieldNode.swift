import Foundation
import AsyncDisplayKit
import Display
import TelegramCore

enum SecureIdRequestedIdentityDocument: Int32 {
    case passport
    case internalPassport
    case driversLicense
    case idCard
    
    var valueKey: SecureIdValueKey {
        switch self {
            case .passport:
                return .passport
            case .internalPassport:
                return .internalPassport
            case .driversLicense:
                return .driversLicense
            case .idCard:
                return .idCard
        }
    }
}

enum SecureIdRequestedAddressDocument: Int32 {
    case passportRegistration
    case temporaryRegistration
    case bankStatement
    case utilityBill
    case rentalAgreement
    
    var valueKey: SecureIdValueKey {
        switch self {
            case .passportRegistration:
                return .passportRegistration
            case .temporaryRegistration:
                return .temporaryRegistration
            case .bankStatement:
                return .bankStatement
            case .utilityBill:
                return .utilityBill
            case .rentalAgreement:
                return .rentalAgreement
        }
    }
}

struct ParsedRequestedPersonalDetails {
    var nativeNames: Bool
}

enum SecureIdParsedRequestedFormField {
    case identity(personalDetails: ParsedRequestedPersonalDetails?, document: ParsedRequestedIdentityDocument?, selfie: Bool, translation: Bool)
    case address(addressDetails: Bool, document: ParsedRequestedAddressDocument?, translation: Bool)
    case phone
    case email
}

enum ParsedRequestedIdentityDocument {
    case just(SecureIdRequestedIdentityDocument)
    case oneOf(Set<SecureIdRequestedIdentityDocument>)
}

enum ParsedRequestedAddressDocument {
    case just(SecureIdRequestedAddressDocument)
    case oneOf(Set<SecureIdRequestedAddressDocument>)
}

private struct RequestedIdentity {
    var details: Bool = false
    var nativeNames: Bool = false
    var documents: [ParsedRequestedIdentityDocument] = []
    var selfie: Bool = false
    var translation: Bool = false
    
    mutating func merge(_ other: RequestedIdentity) {
        self.details = self.details || other.details
        self.nativeNames = self.nativeNames || other.nativeNames
        self.documents.append(contentsOf: other.documents)
        self.selfie = self.selfie || other.selfie
        self.translation = self.translation || other.translation
    }
}

private struct RequestedAddress {
    var details: Bool = false
    var documents: [ParsedRequestedAddressDocument] = []
    var translation: Bool = false
    
    mutating func merge(_ other: RequestedAddress) {
        self.details = self.details || other.details
        self.documents.append(contentsOf: other.documents)
        self.translation = self.translation || other.translation
    }
}

private struct RequestedFieldValues {
    var identity = RequestedIdentity()
    var address = RequestedAddress()
    var phone: Bool = false
    var email: Bool = false
    
    mutating func merge(_ other: RequestedFieldValues) {
        self.identity.merge(other.identity)
        self.address.merge(other.address)
        self.phone = self.phone || other.phone
        self.email = self.email || other.email
    }
}

func parseRequestedFormFields(_ types: [SecureIdRequestedFormField]) -> [SecureIdParsedRequestedFormField] {
    var values = RequestedFieldValues()
    
    for type in types {
        switch type {
            case let .just(value):
                let subResult = parseRequestedFieldValues(type: value)
                values.merge(subResult)
            case let .oneOf(subTypes):
                var oneOfResult = RequestedFieldValues()
                var oneOfIdentity = Set<SecureIdRequestedIdentityDocument>()
                var oneOfAddress = Set<SecureIdRequestedAddressDocument>()
                for type in subTypes {
                    let subResult = parseRequestedFieldValues(type: type)
                    for document in subResult.identity.documents {
                        if case let .just(document) = document {
                            oneOfIdentity.insert(document)
                        }
                    }
                    for document in subResult.address.documents {
                        if case let .just(document) = document {
                            oneOfAddress.insert(document)
                        }
                    }
                    oneOfResult.identity.details = oneOfResult.identity.details || subResult.identity.details
                    oneOfResult.identity.selfie = oneOfResult.identity.selfie || subResult.identity.selfie
                    oneOfResult.identity.translation = oneOfResult.identity.translation || subResult.identity.translation
                    oneOfResult.address.details = oneOfResult.address.details || subResult.address.details
                    oneOfResult.address.translation = oneOfResult.address.translation || subResult.address.translation
                }
                if !oneOfIdentity.isEmpty {
                    oneOfResult.identity.documents.append(.oneOf(oneOfIdentity))
                }
                if !oneOfAddress.isEmpty {
                    oneOfResult.address.documents.append(.oneOf(oneOfAddress))
                }
                values.merge(oneOfResult)
        }
    }
    
    var result: [SecureIdParsedRequestedFormField] = []
    if values.identity.details || !values.identity.documents.isEmpty {
        if values.identity.documents.isEmpty {
            result.append(.identity(personalDetails: ParsedRequestedPersonalDetails(nativeNames: values.identity.nativeNames), document: nil, selfie: false, translation: false))
        } else {
            for document in values.identity.documents {
                result.append(.identity(personalDetails: values.identity.details ? ParsedRequestedPersonalDetails(nativeNames: values.identity.nativeNames) : nil, document: document, selfie: values.identity.selfie, translation: values.identity.translation))
            }
        }
    }
    if values.address.details || !values.address.documents.isEmpty {
        if values.address.documents.isEmpty {
            result.append(.address(addressDetails: true, document: nil, translation: false))
        } else {
            for document in values.address.documents {
                result.append(.address(addressDetails: values.address.details, document: document, translation: values.address.translation))
            }
        }
    }
    if values.phone {
        result.append(.phone)
    }
    if values.email {
        result.append(.email)
    }
    
    return result
}

private func parseRequestedFieldValues(type: SecureIdRequestedFormFieldValue) -> RequestedFieldValues {
    var values = RequestedFieldValues()
    
    switch type {
        case let .personalDetails(nativeNames):
            values.identity.details = true
            values.identity.nativeNames = nativeNames
        case let .passport(selfie, translation):
            values.identity.documents.append(.just(.passport))
            values.identity.selfie = values.identity.selfie || selfie
            values.identity.translation = values.identity.translation || translation
        case let .internalPassport(selfie, translation):
            values.identity.documents.append(.just(.internalPassport))
            values.identity.selfie = values.identity.selfie || selfie
            values.identity.translation = values.identity.translation || translation
        case let .driversLicense(selfie, translation):
            values.identity.documents.append(.just(.driversLicense))
            values.identity.selfie = values.identity.selfie || selfie
            values.identity.translation = values.identity.translation || translation
        case let .idCard(selfie, translation):
            values.identity.documents.append(.just(.idCard))
            values.identity.selfie = values.identity.selfie || selfie
            values.identity.translation = values.identity.translation || translation
        case .address:
            values.address.details = true
        case let .passportRegistration(translation):
            values.address.documents.append(.just(.passportRegistration))
            values.address.translation = values.address.translation || translation
        case let .temporaryRegistration(translation):
            values.address.documents.append(.just(.temporaryRegistration))
            values.address.translation = values.address.translation || translation
        case let .bankStatement(translation):
            values.address.documents.append(.just(.bankStatement))
            values.address.translation = values.address.translation || translation
        case let .utilityBill(translation):
            values.address.documents.append(.just(.utilityBill))
            values.address.translation = values.address.translation || translation
        case let .rentalAgreement(translation):
            values.address.documents.append(.just(.rentalAgreement))
            values.address.translation = values.address.translation || translation
        case .phone:
            values.phone = true
        case .email:
            values.email = true
    }
    return values
}

private let titleFont = Font.regular(17.0)
private let textFont = Font.regular(15.0)

private func fieldsText(_ fields: String...) -> String {
    var result = ""
    for field in fields {
        if !field.isEmpty {
            if !result.isEmpty {
                result.append(", ")
            }
            result.append(field)
        }
    }
    return result
}

private func countryName(code: String, strings: PresentationStrings) -> String {
    return AuthorizationSequenceCountrySelectionController.lookupCountryNameById(code, strings: strings) ?? ""
}

private func fieldTitleAndText(field: SecureIdParsedRequestedFormField, strings: PresentationStrings, values: [SecureIdValueWithContext]) -> (String, String) {
    let title: String
    let placeholder: String
    var text: String = ""
    
    switch field {
        case let .identity(personalDetails, document, _, _):
            if let document = document {
                title = strings.Passport_FieldIdentity
                switch document {
                    case let .just(type):
                        break
                    case let .oneOf(types):
                        break
                }
                placeholder = strings.Passport_FieldIdentityUploadHelp
            } else {
                title = strings.Passport_Identity_TypePersonalDetails
                placeholder = strings.Passport_FieldIdentityDetailsHelp
            }
            
            if personalDetails != nil {
                if let value = findValue(values, key: .personalDetails), case let .personalDetails(personalDetailsValue) = value.1 {
                    if !text.isEmpty {
                        text.append(", ")
                    }
                    text.append(fieldsText(personalDetailsValue.latinName.firstName, personalDetailsValue.latinName.lastName, countryName(code: personalDetailsValue.countryCode, strings: strings)))
                }
            }
        case let .address(addressDetails, document, _):
            if let document = document {
                title = strings.Passport_FieldAddress
                switch document {
                    case let .just(type):
                        break
                    case let .oneOf(types):
                        break
                }
                placeholder = strings.Passport_FieldAddressUploadHelp
            } else {
                title = strings.Passport_FieldAddress
                placeholder = strings.Passport_FieldAddressHelp
            }
            
            if addressDetails {
                if let value = findValue(values, key: .address), case let .address(addressValue) = value.1 {
                    if !text.isEmpty {
                        text.append(", ")
                    }
                    text.append(fieldsText(addressValue.postcode, addressValue.street1, addressValue.street2, addressValue.city))
                }
            }
        case .phone:
            title = strings.Passport_FieldPhone
            placeholder = strings.Passport_FieldPhoneHelp
            
            if let value = findValue(values, key: .phone), case let .phone(phoneValue) = value.1 {
                if !text.isEmpty {
                    text.append(", ")
                }
                text = formatPhoneNumber(phoneValue.phone)
            }
        case .email:
            title = strings.Passport_FieldEmail
            placeholder = strings.Passport_FieldEmailHelp
        
            if let value = findValue(values, key: .email), case let .email(emailValue) = value.1 {
                if !text.isEmpty {
                    text.append(", ")
                }
                text = formatPhoneNumber(emailValue.email)
            }
    }
    
    return (title, text.isEmpty ? placeholder : text)
}

private struct ValueAdditionalData {
    var selfie: Bool = false
    var translation: Bool = false
}

private func extractValueAdditionalData(_ value: SecureIdValue) -> ValueAdditionalData {
    var data = ValueAdditionalData()
    switch value {
        case let .passport(value):
            data.selfie = value.selfieDocument != nil
            data.translation = !value.translations.isEmpty
        case let .internalPassport(value):
            data.selfie = value.selfieDocument != nil
            data.translation = !value.translations.isEmpty
        case let .idCard(value):
            data.selfie = value.selfieDocument != nil
            data.translation = !value.translations.isEmpty
        case let .driversLicense(value):
            data.selfie = value.selfieDocument != nil
            data.translation = !value.translations.isEmpty
        case let .rentalAgreement(value):
            data.translation = !value.translations.isEmpty
        case let .bankStatement(value):
            data.translation = !value.translations.isEmpty
        case let .temporaryRegistration(value):
            data.translation = !value.translations.isEmpty
        case let .passportRegistration(value):
            data.translation = !value.translations.isEmpty
        default:
            break
    }
    return data
}

final class SecureIdAuthFormFieldNode: ASDisplayNode {
    private let selected: () -> Void
    
    private let topSeparatorNode: ASDisplayNode
    private let bottomSeparatorNode: ASDisplayNode
    private let highlightedBackgroundNode: ASDisplayNode
    
    private let titleNode: ImmediateTextNode
    private let textNode: ImmediateTextNode
    private let disclosureNode: ASImageNode
    private let checkNode: ASImageNode
    
    private let buttonNode: HighlightableButtonNode
    
    private var validLayout: (CGFloat, Bool, Bool)?
    
    private let field: SecureIdParsedRequestedFormField
    private let theme: PresentationTheme
    private let strings: PresentationStrings
    
    init(theme: PresentationTheme, strings: PresentationStrings, field: SecureIdParsedRequestedFormField, values: [SecureIdValueWithContext], selected: @escaping () -> Void) {
        self.field = field
        self.theme = theme
        self.strings = strings
        self.selected = selected
        
        self.topSeparatorNode = ASDisplayNode()
        self.topSeparatorNode.isLayerBacked = true
        self.topSeparatorNode.backgroundColor = theme.list.itemBlocksSeparatorColor
        
        self.bottomSeparatorNode = ASDisplayNode()
        self.bottomSeparatorNode.isLayerBacked = true
        self.bottomSeparatorNode.backgroundColor = theme.list.itemBlocksSeparatorColor
        
        self.highlightedBackgroundNode = ASDisplayNode()
        self.highlightedBackgroundNode.isLayerBacked = true
        self.highlightedBackgroundNode.backgroundColor = theme.list.itemHighlightedBackgroundColor
        self.highlightedBackgroundNode.alpha = 0.0
        
        self.titleNode = ImmediateTextNode()
        self.titleNode.displaysAsynchronously = false
        self.titleNode.isLayerBacked = true
        self.titleNode.maximumNumberOfLines = 1
        
        self.textNode = ImmediateTextNode()
        self.textNode.displaysAsynchronously = false
        self.textNode.isLayerBacked = true
        self.textNode.maximumNumberOfLines = 1
        
        self.disclosureNode = ASImageNode()
        self.disclosureNode.isLayerBacked = true
        self.disclosureNode.displayWithoutProcessing = true
        self.disclosureNode.displaysAsynchronously = false
        self.disclosureNode.image = PresentationResourcesItemList.disclosureArrowImage(theme)
        
        self.checkNode = ASImageNode()
        self.checkNode.isLayerBacked = true
        self.checkNode.displayWithoutProcessing = true
        self.checkNode.displaysAsynchronously = false
        self.checkNode.image = PresentationResourcesItemList.checkIconImage(theme)
        
        self.buttonNode = HighlightableButtonNode()
        
        super.init()
        
        self.addSubnode(self.topSeparatorNode)
        self.addSubnode(self.bottomSeparatorNode)
        self.addSubnode(self.highlightedBackgroundNode)
        self.addSubnode(self.titleNode)
        self.addSubnode(self.textNode)
        self.addSubnode(self.disclosureNode)
        self.addSubnode(self.checkNode)
        self.addSubnode(self.buttonNode)
        
        self.updateValues(values)
        
        self.buttonNode.highligthedChanged = { [weak self] highlighted in
            if let strongSelf = self {
                if highlighted {
                    strongSelf.highlightedBackgroundNode.layer.removeAnimation(forKey: "opacity")
                    strongSelf.highlightedBackgroundNode.alpha = 1.0
                    strongSelf.view.superview?.bringSubview(toFront: strongSelf.view)
                } else {
                    strongSelf.highlightedBackgroundNode.alpha = 0.0
                    strongSelf.highlightedBackgroundNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2)
                }
            }
        }
        self.buttonNode.addTarget(self, action: #selector(self.buttonPressed), forControlEvents: .touchUpInside)
    }
    
    func updateValues(_ values: [SecureIdValueWithContext]) {
        var (title, text) = fieldTitleAndText(field: self.field, strings: self.strings, values: values)
        var textColor = self.theme.list.itemSecondaryTextColor
        /*switch self.field {
            case .identity:
                if let error = errors[.personalDetails]?.first {
                    text = error
                    textColor = self.theme.list.itemDestructiveColor
                }
            default:
                break
        }*/
        self.titleNode.attributedText = NSAttributedString(string: title, font: titleFont, textColor: self.theme.list.itemPrimaryTextColor)
        self.textNode.attributedText = NSAttributedString(string: text, font: textFont, textColor: textColor)
        
        var filled = true
        switch self.field {
            case let .identity(personalDetails, document, selfie, translation):
                if personalDetails != nil {
                    if findValue(values, key: .personalDetails) == nil {
                        filled = false
                    }
                }
                if let document = document {
                    switch document {
                        case let .just(type):
                            if let value = findValue(values, key: type.valueKey)?.1 {
                                let data = extractValueAdditionalData(value)
                                if selfie && !data.selfie {
                                    filled = false
                                }
                                if translation && !data.translation {
                                    filled = false
                                }
                            } else {
                                filled = false
                            }
                        case let .oneOf(types):
                            var anyDocument = false
                            for type in types {
                                if let value = findValue(values, key: type.valueKey)?.1 {
                                    let data = extractValueAdditionalData(value)
                                    var dataFilled = true
                                    if selfie && !data.selfie {
                                        dataFilled = false
                                    }
                                    if translation && !data.translation {
                                        dataFilled = false
                                    }
                                    if dataFilled {
                                        anyDocument = true
                                    }
                                }
                            }
                            if !anyDocument {
                                filled = false
                            }
                    }
                }
            case let .address(addressDetails, document, translation):
                if addressDetails {
                    if findValue(values, key: .address) == nil {
                        filled = false
                    }
                }
                if let document = document {
                    switch document {
                        case let .just(type):
                            if let value = findValue(values, key: type.valueKey)?.1 {
                                let data = extractValueAdditionalData(value)
                                if translation && !data.translation {
                                    filled = false
                                }
                            } else {
                                filled = false
                            }
                        case let .oneOf(types):
                            var anyDocument = false
                            for type in types {
                                if let value = findValue(values, key: type.valueKey)?.1 {
                                    let data = extractValueAdditionalData(value)
                                    var dataFilled = true
                                    if translation && !data.translation {
                                        dataFilled = false
                                    }
                                    if dataFilled {
                                        anyDocument = true
                                    }
                                }
                            }
                            if !anyDocument {
                                filled = false
                            }
                    }
                }
            case .phone:
                if findValue(values, key: .phone) == nil {
                    filled = false
                }
            case .email:
                if findValue(values, key: .email) == nil {
                    filled = false
                }
        }
        
        self.checkNode.isHidden = !filled
        self.disclosureNode.isHidden = filled
        
        if let (width, hasPrevious, hasNext) = self.validLayout {
            let _ = self.updateLayout(width: width, hasPrevious: hasPrevious, hasNext: hasNext, transition: .immediate)
        }
    }
    
    func updateLayout(width: CGFloat, hasPrevious: Bool, hasNext: Bool, transition: ContainedViewLayoutTransition) -> CGFloat {
        self.validLayout = (width, hasPrevious, hasNext)
        let leftInset: CGFloat = 16.0
        let rightInset: CGFloat = 16.0
        let height: CGFloat = 64.0
        
        let rightTextInset = rightInset + 24.0
        
        let titleTextSpacing: CGFloat = 5.0
        
        let titleSize = self.titleNode.updateLayout(CGSize(width: width - leftInset - rightTextInset, height: 100.0))
        let textSize = self.textNode.updateLayout(CGSize(width: width - leftInset - rightTextInset, height: 100.0))
        
        let textOrigin = floor((height - titleSize.height - titleTextSpacing - textSize.height) / 2.0)
        let titleFrame = CGRect(origin: CGPoint(x: leftInset, y: textOrigin), size: titleSize)
        self.titleNode.frame = titleFrame
        let textFrame = CGRect(origin: CGPoint(x: leftInset, y: titleFrame.maxY + titleTextSpacing), size: textSize)
        self.textNode.frame = textFrame
        
        transition.updateFrame(node: self.topSeparatorNode, frame: CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: CGSize(width: width, height: UIScreenPixel)))
        transition.updateAlpha(node: self.topSeparatorNode, alpha: hasPrevious ? 0.0 : 1.0)
        let bottomSeparatorInset: CGFloat = hasNext ? leftInset : 0.0
        transition.updateFrame(node: self.bottomSeparatorNode, frame: CGRect(origin: CGPoint(x: bottomSeparatorInset, y: height - UIScreenPixel), size: CGSize(width: width - bottomSeparatorInset, height: UIScreenPixel)))
        
        transition.updateFrame(node: self.buttonNode, frame: CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: CGSize(width: width, height: height)))
        transition.updateFrame(node: self.highlightedBackgroundNode, frame: CGRect(origin: CGPoint(x: 0.0, y: -(hasPrevious ? UIScreenPixel : 0.0)), size: CGSize(width: width, height: height + (hasPrevious ? UIScreenPixel : 0.0))))
        
        if let image = self.disclosureNode.image {
            self.disclosureNode.frame = CGRect(origin: CGPoint(x: width - 15.0 - image.size.width, y: floor((height - image.size.height) / 2.0)), size: image.size)
        }
        
        if let image = self.checkNode.image {
            self.checkNode.frame = CGRect(origin: CGPoint(x: width - 15.0 - image.size.width, y: floor((height - image.size.height) / 2.0)), size: image.size)
        }
        
        return height
    }
    
    @objc private func buttonPressed() {
        self.selected()
    }
}