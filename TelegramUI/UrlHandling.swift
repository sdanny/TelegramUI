import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import MtProtoKitDynamic

enum ParsedInternalPeerUrlParameter {
    case botStart(String)
    case groupBotStart(String)
    case channelMessage(Int32)
}

enum WallpaperUrlParameter {
    case slug(String, WallpaperPresentationOptions, UIColor?, Int32?)
    case color(UIColor)
}

enum ParsedInternalUrl {
    case peerName(String, ParsedInternalPeerUrlParameter?)
    case stickerPack(String)
    case join(String)
    case localization(String)
    case proxy(host: String, port: Int32, username: String?, password: String?, secret: Data?)
    case internalInstantView(url: String)
    case confirmationCode(Int)
    case cancelAccountReset(phone: String, hash: String)
    case share(url: String?, text: String?, to: String?)
    case wallpaper(WallpaperUrlParameter)
}

private enum ParsedUrl {
    case externalUrl(String)
    case internalUrl(ParsedInternalUrl)
}

enum ResolvedUrl {
    case externalUrl(String)
    case peer(PeerId?, ChatControllerInteractionNavigateToPeer)
    case botStart(peerId: PeerId, payload: String)
    case groupBotStart(peerId: PeerId, payload: String)
    case channelMessage(peerId: PeerId, messageId: MessageId)
    case stickerPack(name: String)
    case instantView(TelegramMediaWebpage, String?)
    case proxy(host: String, port: Int32, username: String?, password: String?, secret: Data?)
    case join(String)
    case localization(String)
    case confirmationCode(Int)
    case cancelAccountReset(phone: String, hash: String)
    case share(url: String?, text: String?, to: String?)
    case wallpaper(WallpaperUrlParameter)
}

func parseInternalUrl(query: String) -> ParsedInternalUrl? {
    if let components = URLComponents(string: "/" + query) {
        var pathComponents = components.path.components(separatedBy: "/")
        if !pathComponents.isEmpty {
            pathComponents.removeFirst()
        }
        if !pathComponents.isEmpty && !pathComponents[0].isEmpty {
            let peerName: String = pathComponents[0]
            if pathComponents.count == 1 {
                if let queryItems = components.queryItems {
                    if peerName == "socks" || peerName == "proxy" {
                        var server: String?
                        var port: String?
                        var user: String?
                        var pass: String?
                        var secret: Data?
                        if let queryItems = components.queryItems {
                            for queryItem in queryItems {
                                if let value = queryItem.value {
                                    if queryItem.name == "server" || queryItem.name == "proxy" {
                                        server = value
                                    } else if queryItem.name == "port" {
                                        port = value
                                    } else if queryItem.name == "user" {
                                        user = value
                                    } else if queryItem.name == "pass" {
                                        pass = value
                                    } else if queryItem.name == "secret" {
                                        let data = dataWithHexString(value)
                                        if data.count == 16 || (data.count == 17 && MTSocksProxySettings.secretSupportsExtendedPadding(data)) {
                                            secret = data
                                        }
                                    }
                                }
                            }
                        }
                        
                        if let server = server, !server.isEmpty, let port = port, let portValue = Int32(port) {
                            return .proxy(host: server, port: portValue, username: user, password: pass, secret: secret)
                        }
                    } else if peerName == "iv" {
                        var url: String?
                        for queryItem in queryItems {
                            if let value = queryItem.value {
                                if queryItem.name == "url" {
                                    url = value
                                }
                            }
                        }
                        if let _ = url {
                            return .internalInstantView(url: "https://t.me/\(query)")
                        }
                    } else if peerName == "login" {
                        var code: String?
                        for queryItem in queryItems {
                            if let value = queryItem.value {
                                if queryItem.name == "code" {
                                    code = value
                                }
                            }
                        }
                        if let code = code, let codeValue = Int(code) {
                            return .confirmationCode(codeValue)
                        }
                    } else if peerName == "confirmphone" {
                        var phone: String?
                        var hash: String?
                        for queryItem in queryItems {
                            if let value = queryItem.value {
                                if queryItem.name == "phone" {
                                    phone = value
                                } else if queryItem.name == "hash" {
                                    hash = value
                                }
                            }
                        }
                        if let phone = phone, let hash = hash {
                            return .cancelAccountReset(phone: phone, hash: hash)
                        }
                    } else {
                        for queryItem in queryItems {
                            if let value = queryItem.value {
                                if queryItem.name == "start" {
                                    return .peerName(peerName, .botStart(value))
                                } else if queryItem.name == "startgroup" {
                                    return .peerName(peerName, .groupBotStart(value))
                                } else if queryItem.name == "game" {
                                    return nil
                                }
                            }
                        }
                    }
                }
                return .peerName(peerName, nil)
            } else if pathComponents.count == 2 || pathComponents.count == 3 {
                if pathComponents[0] == "addstickers" {
                    return .stickerPack(pathComponents[1])
                } else if pathComponents[0] == "joinchat" || pathComponents[0] == "joinchannel" {
                    return .join(pathComponents[1])
                } else if pathComponents[0] == "setlanguage" {
                    return .localization(pathComponents[1])
                } else if pathComponents[0] == "login" {
                    if let code = Int(pathComponents[1]) {
                        return .confirmationCode(code)
                    }
                } else if pathComponents[0] == "share" && pathComponents[1] == "url" {
                    if let queryItems = components.queryItems {
                        var url: String?
                        var text: String?
                        for queryItem in queryItems {
                            if let value = queryItem.value {
                                if queryItem.name == "url" {
                                    url = value
                                } else if queryItem.name == "text" {
                                    text = value
                                }
                            }
                        }
                        
                        if let url = url {
                            return .share(url: url, text: text, to: nil)
                        }
                    }
                    return nil
                } else if pathComponents[0] == "bg" {
                    let component = pathComponents[1]
                    let parameter: WallpaperUrlParameter
                    if component.count == 6, component.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789abcdefABCDEF").inverted) == nil, let color = UIColor(hexString: component) {
                        parameter = .color(color)
                    } else {
                        var options: WallpaperPresentationOptions = []
                        var intensity: Int32?
                        var color: UIColor?
                        if let queryItems = components.queryItems {
                            for queryItem in queryItems {
                                if let value = queryItem.value{
                                    if queryItem.name == "mode" {
                                        for option in value.components(separatedBy: "+") {
                                            switch option.lowercased() {
                                                case "motion":
                                                    options.insert(.motion)
                                                case "blur":
                                                    options.insert(.blur)
                                                default:
                                                    break
                                            }
                                        }
                                    } else if queryItem.name == "bg_color" {
                                        color = UIColor(hexString: value)
                                    } else if queryItem.name == "intensity" {
                                        intensity = Int32(value)
                                    }
                                }
                            }
                        }
                        parameter = .slug(component, options, color, intensity)
                    }
                    return .wallpaper(parameter)
                } else if let value = Int(pathComponents[1]) {
                    return .peerName(peerName, .channelMessage(Int32(value)))
                } else {
                    return nil
                }
            }
        } else {
            return nil
        }
    }
    return nil
}

private func resolveInternalUrl(account: Account, url: ParsedInternalUrl) -> Signal<ResolvedUrl?, NoError> {
    switch url {
        case let .peerName(name, parameter):
            return resolvePeerByName(account: account, name: name)
            |> take(1)
            |> mapToSignal { peerId -> Signal<Peer?, NoError> in
                return account.postbox.transaction { transaction -> Peer? in
                    if let peerId = peerId {
                        return transaction.getPeer(peerId)
                    } else {
                        return nil
                    }
                }
            }
            |> map { peer -> ResolvedUrl? in
                if let peer = peer {
                    if let parameter = parameter {
                        switch parameter {
                            case let .botStart(payload):
                                return .botStart(peerId: peer.id, payload: payload)
                            case let .groupBotStart(payload):
                                return .groupBotStart(peerId: peer.id, payload: payload)
                            case let .channelMessage(id):
                                return .channelMessage(peerId: peer.id, messageId: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: id))
                        }
                    } else {
                        if let peer = peer as? TelegramUser, peer.botInfo == nil {
                            return .peer(peer.id, .info)
                        } else {
                            return .peer(peer.id, .chat(textInputState: nil, messageId: nil))
                        }
                    }
                } else {
                    return .peer(nil, .info)
                }
            }
        case let .stickerPack(name):
            return .single(.stickerPack(name: name))
        case let .join(link):
            return .single(.join(link))
        case let .localization(identifier):
            return .single(.localization(identifier))
        case let .proxy(host, port, username, password, secret):
            return .single(.proxy(host: host, port: port, username: username, password: password, secret: secret))
        case let .internalInstantView(url):
            return resolveInstantViewUrl(account: account, url: url)
            |> map(Optional.init)
        case let .confirmationCode(code):
            return .single(.confirmationCode(code))
        case let .cancelAccountReset(phone, hash):
            return .single(.cancelAccountReset(phone: phone, hash: hash))
        case let .share(url, text, to):
            return .single(.share(url: url, text: text, to: to))
        case let .wallpaper(parameter):
            return .single(.wallpaper(parameter))
    }
}

func isTelegramMeLink(_ url: String) -> Bool {
    let schemes = ["http://", "https://", ""]
    let baseTelegramMePaths = ["telegram.me", "t.me"]
    for basePath in baseTelegramMePaths {
        for scheme in schemes {
            let basePrefix = scheme + basePath + "/"
            if url.lowercased().hasPrefix(basePrefix) {
                return true
            }
        }
    }
    return false
}

func parseProxyUrl(_ url: String) -> (host: String, port: Int32, username: String?, password: String?, secret: Data?)? {
    let schemes = ["http://", "https://", ""]
    let baseTelegramMePaths = ["telegram.me", "t.me"]
    for basePath in baseTelegramMePaths {
        for scheme in schemes {
            let basePrefix = scheme + basePath + "/"
            if url.lowercased().hasPrefix(basePrefix) {
                if let internalUrl = parseInternalUrl(query: String(url[basePrefix.endIndex...])), case let .proxy(proxy) = internalUrl {
                    return (proxy.host, proxy.port, proxy.username, proxy.password, proxy.secret)
                }
            }
        }
    }
    if let parsedUrl = URL(string: url), parsedUrl.scheme == "tg", let host = parsedUrl.host, let query = parsedUrl.query {
        if let internalUrl = parseInternalUrl(query: host + "?" + query), case let .proxy(proxy) = internalUrl {
            return (proxy.host, proxy.port, proxy.username, proxy.password, proxy.secret)
        }
    }
    
    return nil
}

func parseWallpaperUrl(_ url: String) -> WallpaperUrlParameter? {
    let schemes = ["http://", "https://", ""]
    let baseTelegramMePaths = ["telegram.me", "t.me"]
    for basePath in baseTelegramMePaths {
        for scheme in schemes {
            let basePrefix = scheme + basePath + "/"
            if url.lowercased().hasPrefix(basePrefix) {
                if let internalUrl = parseInternalUrl(query: String(url[basePrefix.endIndex...])), case let .wallpaper(wallpaper) = internalUrl {
                    return wallpaper
                }
            }
        }
    }
    if let parsedUrl = URL(string: url), parsedUrl.scheme == "tg", let host = parsedUrl.host, let query = parsedUrl.query {
        if let internalUrl = parseInternalUrl(query: host + "?" + query), case let .wallpaper(wallpaper) = internalUrl {
            return wallpaper
        }
    }
    
    return nil
}

func resolveUrl(account: Account, url: String) -> Signal<ResolvedUrl, NoError> {
    let schemes = ["http://", "https://", ""]
    let baseTelegramMePaths = ["telegram.me", "t.me"]
    for basePath in baseTelegramMePaths {
        for scheme in schemes {
            let basePrefix = scheme + basePath + "/"
            if url.lowercased().hasPrefix(basePrefix) {
                if let internalUrl = parseInternalUrl(query: String(url[basePrefix.endIndex...])) {
                    return resolveInternalUrl(account: account, url: internalUrl)
                    |> map { resolved -> ResolvedUrl in
                        if let resolved = resolved {
                            return resolved
                        } else {
                            return .externalUrl(url)
                        }
                    }
                } else {
                    return .single(.externalUrl(url))
                }
            }
        }
    }
    let baseTelegraPhPaths = ["telegra.ph/", "t.me/iv?"]
    for basePath in baseTelegraPhPaths {
        for scheme in schemes {
            let basePrefix = scheme + basePath
            if url.lowercased().hasPrefix(basePrefix) {
                return resolveInstantViewUrl(account: account, url: url)
            }
        }
    }
    return .single(.externalUrl(url))
}

func resolveInstantViewUrl(account: Account, url: String) -> Signal<ResolvedUrl, NoError> {
    return webpagePreview(account: account, url: url)
    |> mapToSignal { webpage -> Signal<ResolvedUrl, NoError> in
        if let webpage = webpage {
            if case let .Loaded(content) = webpage.content {
                if content.instantPage != nil {
                    var anchorValue: String?
                    if let anchorRange = url.range(of: "#") {
                        let anchor = url[anchorRange.upperBound...]
                        if !anchor.isEmpty {
                            anchorValue = String(anchor)
                        }
                    }
                    return .single(.instantView(webpage, anchorValue))
                } else {
                    return .single(.externalUrl(url))
                }
            } else {
                return .complete()
            }
        } else {
            return .single(.externalUrl(url))
        }
    }
}
