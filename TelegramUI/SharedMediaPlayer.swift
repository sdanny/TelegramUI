import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore

import TelegramUIPrivateModule

enum SharedMediaPlayerPlaybackControlAction {
    case play
    case pause
    case togglePlayPause
}

enum SharedMediaPlayerControlAction {
    case next
    case previous
    case playback(SharedMediaPlayerPlaybackControlAction)
    case seek(Double)
    case setOrder(MusicPlaybackSettingsOrder)
    case setLooping(MusicPlaybackSettingsLooping)
    case setBaseRate(AudioPlaybackRate)
}

enum SharedMediaPlaylistControlAction {
    case next
    case previous
}

enum SharedMediaPlaybackDataType {
    case music
    case voice
    case instantVideo
}

enum SharedMediaPlaybackDataSource: Equatable {
    case telegramFile(FileMediaReference)
    
    static func ==(lhs: SharedMediaPlaybackDataSource, rhs: SharedMediaPlaybackDataSource) -> Bool {
        switch lhs {
            case let .telegramFile(lhsFileReference):
                if case let .telegramFile(rhsFileReference) = rhs {
                    if !lhsFileReference.media.isEqual(to: rhsFileReference.media) {
                        return false
                    }
                    return true
                } else {
                    return false
                }
        }
    }
}

struct SharedMediaPlaybackData: Equatable {
    let type: SharedMediaPlaybackDataType
    let source: SharedMediaPlaybackDataSource
    
    static func ==(lhs: SharedMediaPlaybackData, rhs: SharedMediaPlaybackData) -> Bool {
        return lhs.type == rhs.type && lhs.source == rhs.source
    }
}

struct SharedMediaPlaybackAlbumArt: Equatable {
    let thumbnailResource: TelegramMediaResource
    let fullSizeResource: TelegramMediaResource
    
    static func ==(lhs: SharedMediaPlaybackAlbumArt, rhs: SharedMediaPlaybackAlbumArt) -> Bool {
        if !lhs.thumbnailResource.isEqual(to: rhs.thumbnailResource) {
            return false
        }
        
        if !lhs.fullSizeResource.isEqual(to: rhs.fullSizeResource) {
            return false
        }
        
        return true
    }
}

enum SharedMediaPlaybackDisplayData: Equatable {
    case music(title: String?, performer: String?, albumArt: SharedMediaPlaybackAlbumArt?)
    case voice(author: Peer?, peer: Peer?)
    case instantVideo(author: Peer?, peer: Peer?, timestamp: Int32)
    
    static func ==(lhs: SharedMediaPlaybackDisplayData, rhs: SharedMediaPlaybackDisplayData) -> Bool {
        switch lhs {
            case let .music(lhsTitle, lhsPerformer, lhsAlbumArt):
                if case let .music(rhsTitle, rhsPerformer, rhsAlbumArt) = rhs, lhsTitle == rhsTitle, lhsPerformer == rhsPerformer, lhsAlbumArt == rhsAlbumArt {
                    return true
                } else {
                    return false
                }
            case let .voice(lhsAuthor, lhsPeer):
                if case let .voice(rhsAuthor, rhsPeer) = rhs, arePeersEqual(lhsAuthor, rhsAuthor), arePeersEqual(lhsPeer, rhsPeer) {
                    return true
                } else {
                    return false
                }
            case let .instantVideo(lhsAuthor, lhsPeer, lhsTimestamp):
                if case let .instantVideo(rhsAuthor, rhsPeer, rhsTimestamp) = rhs, arePeersEqual(lhsAuthor, rhsAuthor), arePeersEqual(lhsPeer, rhsPeer), lhsTimestamp == rhsTimestamp {
                    return true
                } else {
                    return false
                }
        }
    }
}

protocol SharedMediaPlaylistItem {
    var stableId: AnyHashable { get }
    var id: SharedMediaPlaylistItemId { get }
    var playbackData: SharedMediaPlaybackData? { get }
    var displayData: SharedMediaPlaybackDisplayData? { get }
}

func arePlaylistItemsEqual(_ lhs: SharedMediaPlaylistItem?, _ rhs: SharedMediaPlaylistItem?) -> Bool {
    if lhs?.stableId != rhs?.stableId {
        return false
    }
    if lhs?.playbackData != rhs?.playbackData {
        return false
    }
    if lhs?.displayData != rhs?.displayData {
        return false
    }
    return true
}

final class SharedMediaPlaylistState: Equatable {
    let loading: Bool
    let playedToEnd: Bool
    let item: SharedMediaPlaylistItem?
    let nextItem: SharedMediaPlaylistItem?
    let previousItem: SharedMediaPlaylistItem?
    let order: MusicPlaybackSettingsOrder
    let looping: MusicPlaybackSettingsLooping
    
    init(loading: Bool, playedToEnd: Bool, item: SharedMediaPlaylistItem?, nextItem: SharedMediaPlaylistItem?, previousItem: SharedMediaPlaylistItem?, order: MusicPlaybackSettingsOrder, looping: MusicPlaybackSettingsLooping) {
        self.loading = loading
        self.playedToEnd = playedToEnd
        self.item = item
        self.nextItem = nextItem
        self.previousItem = previousItem
        self.order = order
        self.looping = looping
    }
    
    static func ==(lhs: SharedMediaPlaylistState, rhs: SharedMediaPlaylistState) -> Bool {
        if lhs.loading != rhs.loading {
            return false
        }
        if !arePlaylistItemsEqual(lhs.item, rhs.item) {
            return false
        }
        if !arePlaylistItemsEqual(lhs.nextItem, rhs.nextItem) {
            return false
        }
        if !arePlaylistItemsEqual(lhs.previousItem, rhs.previousItem) {
            return false
        }
        if lhs.order != rhs.order {
            return false
        }
        if lhs.looping != rhs.looping {
            return false
        }
        return true
    }
}

protocol SharedMediaPlaylistId {
    func isEqual(to: SharedMediaPlaylistId) -> Bool
}

protocol SharedMediaPlaylistItemId {
    func isEqual(to: SharedMediaPlaylistItemId) -> Bool
}

func areSharedMediaPlaylistItemIdsEqual(_ lhs: SharedMediaPlaylistItemId?, _ rhs: SharedMediaPlaylistItemId?) -> Bool {
    if let lhs = lhs, let rhs = rhs {
        return lhs.isEqual(to: rhs)
    } else if (lhs != nil) != (rhs != nil) {
        return false
    } else {
        return true
    }
}

protocol SharedMediaPlaylistLocation {
    func isEqual(to: SharedMediaPlaylistLocation) -> Bool
}

protocol SharedMediaPlaylist: class {
    var id: SharedMediaPlaylistId { get }
    var location: SharedMediaPlaylistLocation { get }
    var state: Signal<SharedMediaPlaylistState, NoError> { get }
    var looping: MusicPlaybackSettingsLooping { get }
    var currentItemDisappeared: (() -> Void)? { get set }
        
    func control(_ action: SharedMediaPlaylistControlAction)
    func setOrder(_ order: MusicPlaybackSettingsOrder)
    func setLooping(_ looping: MusicPlaybackSettingsLooping)
    
    func onItemPlaybackStarted(_ item: SharedMediaPlaylistItem)
}

final class SharedMediaPlayerItemPlaybackState: Equatable {
    let playlistId: SharedMediaPlaylistId
    let playlistLocation: SharedMediaPlaylistLocation
    let item: SharedMediaPlaylistItem
    let status: MediaPlayerStatus
    let order: MusicPlaybackSettingsOrder
    let looping: MusicPlaybackSettingsLooping
    let playerIndex: Int32
    
    init(playlistId: SharedMediaPlaylistId, playlistLocation: SharedMediaPlaylistLocation, item: SharedMediaPlaylistItem, status: MediaPlayerStatus, order: MusicPlaybackSettingsOrder, looping: MusicPlaybackSettingsLooping, playerIndex: Int32) {
        self.playlistId = playlistId
        self.playlistLocation = playlistLocation
        self.item = item
        self.status = status
        self.order = order
        self.looping = looping
        self.playerIndex = playerIndex
    }
    
    static func ==(lhs: SharedMediaPlayerItemPlaybackState, rhs: SharedMediaPlayerItemPlaybackState) -> Bool {
        if !lhs.playlistId.isEqual(to: rhs.playlistId) {
            return false
        }
        if !arePlaylistItemsEqual(lhs.item, rhs.item) {
            return false
        }
        if lhs.status != rhs.status {
            return false
        }
        if lhs.playerIndex != rhs.playerIndex {
            return false
        }
        if lhs.order != rhs.order {
            return false
        }
        if lhs.looping != rhs.looping {
            return false
        }
        return true
    }
}

enum SharedMediaPlayerState: Equatable {
    case loading
    case item(SharedMediaPlayerItemPlaybackState)
    
    static func ==(lhs: SharedMediaPlayerState, rhs: SharedMediaPlayerState) -> Bool {
        switch lhs {
            case .loading:
                if case .loading = rhs {
                    return true
                } else {
                    return false
                }
            case let .item(item):
                if case .item(item) = rhs {
                    return true
                } else {
                    return false
                }
        }
    }
}

private enum SharedMediaPlaybackItem: Equatable {
    case audio(MediaPlayer)
    case instantVideo(OverlayInstantVideoNode)
    
    var playbackStatus: Signal<MediaPlayerStatus, NoError> {
        switch self {
            case let .audio(player):
                return player.status
            case let .instantVideo(node):
                return node.status |> map { status in
                    if let status = status {
                        return status
                    } else {
                        return MediaPlayerStatus(generationTimestamp: 0.0, duration: 0.0, dimensions: CGSize(), timestamp: 0.0, baseRate: 1.0, seekId: 0, status: .paused, soundEnabled: true)
                    }
                }
        }
    }
    
    static func ==(lhs: SharedMediaPlaybackItem, rhs: SharedMediaPlaybackItem) -> Bool {
        switch lhs {
            case let .audio(lhsPlayer):
                if case let .audio(rhsPlayer) = rhs, lhsPlayer === rhsPlayer {
                    return true
                } else {
                    return false
                }
            case let .instantVideo(lhsNode):
                if case let .instantVideo(rhsNode) = rhs, lhsNode === rhsNode {
                    return true
                } else {
                    return false
                }
        }
    }
    
    func setActionAtEnd(_ f: @escaping () -> Void) {
        switch self {
            case let .audio(player):
                player.actionAtEnd = .action(f)
            case let .instantVideo(node):
                node.playbackEnded = f
        }
    }
    
    func play() {
        switch self {
            case let .audio(player):
                player.play()
            case let .instantVideo(node):
                node.play()
        }
    }
    
    func pause() {
        switch self {
            case let .audio(player):
                player.pause()
            case let .instantVideo(node):
                node.pause()
        }
    }
    
    func togglePlayPause() {
        switch self {
            case let .audio(player):
                player.togglePlayPause()
            case let .instantVideo(node):
                node.togglePlayPause()
        }
    }
    
    func seek(_ timestamp: Double) {
        switch self {
            case let .audio(player):
                player.seek(timestamp: timestamp)
            case let .instantVideo(node):
                node.seek(timestamp)
        }
    }
    
    func setSoundEnabled(_ value: Bool) {
        switch self {
            case .audio:
                break
            case let .instantVideo(node):
                node.setSoundEnabled(value)
        }
    }
    
    func setForceAudioToSpeaker(_ value: Bool) {
        switch self {
            case let .audio(player):
                player.setForceAudioToSpeaker(value)
            case let .instantVideo(node):
                node.setForceAudioToSpeaker(value)
        }
    }
}

final class SharedMediaPlayer {
    private weak var mediaManager: MediaManager?
    let account: Account
    private let audioSession: ManagedAudioSession
    private let overlayMediaManager: OverlayMediaManager
    private let playerIndex: Int32
    private let playlist: SharedMediaPlaylist
    
    private var playbackRate: AudioPlaybackRate
    
    private var proximityManagerIndex: Int?
    private let controlPlaybackWithProximity: Bool
    private var forceAudioToSpeaker = false
    
    private var stateDisposable: Disposable?
    
    private var stateValue: SharedMediaPlaylistState? {
        didSet {
            if self.stateValue != oldValue {
                self.state.set(.single(self.stateValue))
            }
        }
    }
    private let state = Promise<SharedMediaPlaylistState?>(nil)
    
    private var playbackStateValueDisposable: Disposable?
    private var _playbackStateValue: SharedMediaPlayerState?
    private let playbackStateValue = Promise<SharedMediaPlayerState?>()
    var playbackState: Signal<SharedMediaPlayerState?, NoError> {
        return self.playbackStateValue.get()
    }
    
    private var playbackItem: SharedMediaPlaybackItem?
    private var currentPlayedToEnd = false
    private var scheduledPlaybackAction: SharedMediaPlayerPlaybackControlAction?
    
    private let markItemAsPlayedDisposable = MetaDisposable()
    
    var playedToEnd: (() -> Void)?
    var cancelled: (() -> Void)?
    
    private var inForegroundDisposable: Disposable?
    
    private var currentPrefetchItems: (SharedMediaPlaybackDataSource, SharedMediaPlaybackDataSource)?
    private let prefetchDisposable = MetaDisposable()
    
    init(mediaManager: MediaManager, inForeground: Signal<Bool, NoError>, account: Account, audioSession: ManagedAudioSession, overlayMediaManager: OverlayMediaManager, playlist: SharedMediaPlaylist, initialOrder: MusicPlaybackSettingsOrder, initialLooping: MusicPlaybackSettingsLooping, initialPlaybackRate: AudioPlaybackRate, playerIndex: Int32, controlPlaybackWithProximity: Bool) {
        self.mediaManager = mediaManager
        self.account = account
        self.audioSession = audioSession
        self.overlayMediaManager = overlayMediaManager
        playlist.setOrder(initialOrder)
        playlist.setLooping(initialLooping)
        self.playlist = playlist
        self.playerIndex = playerIndex
        self.playbackRate = initialPlaybackRate
        self.controlPlaybackWithProximity = controlPlaybackWithProximity
        
        if controlPlaybackWithProximity {
            self.forceAudioToSpeaker = !DeviceProximityManager.shared().currentValue()
        }
        
        playlist.currentItemDisappeared = { [weak self] in
            self?.cancelled?()
        }
        
        self.stateDisposable = (playlist.state
        |> deliverOnMainQueue).start(next: { [weak self] state in
            if let strongSelf = self {
                let previousPlaybackItem = strongSelf.playbackItem
                strongSelf.updatePrefetchItems(item: state.item, previousItem: state.previousItem, nextItem: state.nextItem, ordering: state.order)
                if state.item?.playbackData != strongSelf.stateValue?.item?.playbackData {
                    if let playbackItem = strongSelf.playbackItem {
                        switch playbackItem {
                            case .audio:
                                playbackItem.pause()
                            case let .instantVideo(node):
                               node.setSoundEnabled(false)
                               strongSelf.overlayMediaManager.controller?.removeNode(node)
                        }
                    }
                    strongSelf.playbackItem = nil
                    if let item = state.item, let playbackData = item.playbackData {
                        let rateValue: Double
                        if case .music = playbackData.type {
                            rateValue = 1.0
                        } else {
                            switch strongSelf.playbackRate {
                                case .x1:
                                    rateValue = 1.0
                                case .x2:
                                    rateValue = 1.8
                            }
                        }
                        
                        switch playbackData.type {
                            case .voice, .music:
                                switch playbackData.source {
                                    case let .telegramFile(fileReference):
                                        strongSelf.playbackItem = .audio(MediaPlayer(audioSessionManager: strongSelf.audioSession, postbox: strongSelf.account.postbox, resourceReference: fileReference.resourceReference(fileReference.media.resource), streamable: playbackData.type == .music ? .conservative : .none, video: false, preferSoftwareDecoding: false, enableSound: true, baseRate: rateValue, fetchAutomatically: true, playAndRecord: controlPlaybackWithProximity))
                                }
                            case .instantVideo:
                                if let mediaManager = strongSelf.mediaManager, let item = item as? MessageMediaPlaylistItem {
                                    switch playbackData.source {
                                        case let .telegramFile(fileReference):
                                            let videoNode = OverlayInstantVideoNode(postbox: strongSelf.account.postbox, audioSession: strongSelf.audioSession, manager: mediaManager.universalVideoManager, content: NativeVideoContent(id: .message(item.message.id, item.message.stableId, fileReference.media.fileId), fileReference: fileReference, enableSound: false, baseRate: rateValue), close: { [weak mediaManager] in
                                                mediaManager?.setPlaylist(nil, type: .voice)
                                            })
                                            strongSelf.playbackItem = .instantVideo(videoNode)
                                            videoNode.setSoundEnabled(true)
                                        videoNode.setBaseRate(rateValue)
                                    }
                                }
                        }
                    }
                    if let playbackItem = strongSelf.playbackItem {
                        playbackItem.setForceAudioToSpeaker(strongSelf.forceAudioToSpeaker)
                        playbackItem.setActionAtEnd({
                            Queue.mainQueue().async {
                                if let strongSelf = self {
                                    switch strongSelf.playlist.looping {
                                        case .item:
                                            strongSelf.playbackItem?.seek(0.0)
                                            strongSelf.playbackItem?.play()
                                        default:
                                            strongSelf.scheduledPlaybackAction = .play
                                            strongSelf.control(.next)
                                    }
                                }
                            }
                        })
                        switch playbackItem {
                            case .audio:
                                break
                            case let .instantVideo(node):
                                strongSelf.overlayMediaManager.controller?.addNode(node)
                        }
                        
                        if let scheduledPlaybackAction = strongSelf.scheduledPlaybackAction {
                            strongSelf.scheduledPlaybackAction = nil
                            switch scheduledPlaybackAction {
                                case .play:
                                    switch playbackItem {
                                        case let .audio(player):
                                            player.play()
                                        case let .instantVideo(node):
                                            node.playOnceWithSound(playAndRecord: controlPlaybackWithProximity)
                                    }
                                case .pause:
                                    playbackItem.pause()
                                case .togglePlayPause:
                                    playbackItem.togglePlayPause()
                            }
                        }
                    }
                }
                
                if strongSelf.currentPlayedToEnd != state.playedToEnd {
                    strongSelf.currentPlayedToEnd = state.playedToEnd
                    if state.playedToEnd {
                        if let playbackItem = strongSelf.playbackItem {
                            switch playbackItem {
                                case let .audio(player):
                                    player.pause()
                                case let .instantVideo(node):
                                    node.setSoundEnabled(false)
                            }
                        }
                        //strongSelf.playbackItem?.seek(0.0)
                        strongSelf.playedToEnd?()
                    }
                }
                
                let updatePlaybackState = strongSelf.stateValue != state || strongSelf.playbackItem != previousPlaybackItem
                strongSelf.stateValue = state
                
                if updatePlaybackState {
                    let playlistId = strongSelf.playlist.id
                    let playlistLocation = strongSelf.playlist.location
                    let playerIndex = strongSelf.playerIndex
                    if let playbackItem = strongSelf.playbackItem, let item = state.item {
                        strongSelf.playbackStateValue.set(playbackItem.playbackStatus
                        |> map { itemStatus in
                            return .item(SharedMediaPlayerItemPlaybackState(playlistId: playlistId, playlistLocation: playlistLocation, item: item, status: itemStatus, order: state.order, looping: state.looping, playerIndex: playerIndex))
                        })
                    strongSelf.markItemAsPlayedDisposable.set((playbackItem.playbackStatus
                        |> filter { status in
                            if case .playing = status.status {
                                return true
                            } else {
                                return false
                            }
                        }
                        |> take(1)
                        |> deliverOnMainQueue).start(next: { next in
                            if let strongSelf = self {
                                strongSelf.playlist.onItemPlaybackStarted(item)
                            }
                        }))
                    } else {
                        if state.item != nil || state.loading {
                            strongSelf.playbackStateValue.set(.single(.loading))
                        } else {
                            strongSelf.playbackStateValue.set(.single(nil))
                            if !state.loading {
                                if let proximityManagerIndex = strongSelf.proximityManagerIndex {
                                    DeviceProximityManager.shared().remove(proximityManagerIndex)
                                }
                            }
                        }
                    }
                }
            }
        })
        
        self.playbackStateValueDisposable = (self.playbackState
        |> deliverOnMainQueue).start(next: { [weak self] value in
            self?._playbackStateValue = value
        })
        
        if controlPlaybackWithProximity {
            self.proximityManagerIndex = DeviceProximityManager.shared().add { [weak self] value in
                let forceAudioToSpeaker = !value
                if let strongSelf = self, strongSelf.forceAudioToSpeaker != forceAudioToSpeaker {
                    strongSelf.forceAudioToSpeaker = forceAudioToSpeaker
                    strongSelf.playbackItem?.setForceAudioToSpeaker(forceAudioToSpeaker)
                    if !forceAudioToSpeaker {
                        strongSelf.control(.playback(.play))
                    } else {
                        strongSelf.control(.playback(.pause))
                    }
                }
            }
        }
    }
    
    deinit {
        self.stateDisposable?.dispose()
        self.markItemAsPlayedDisposable.dispose()
        self.inForegroundDisposable?.dispose()
        self.playbackStateValueDisposable?.dispose()
        self.prefetchDisposable.dispose()
        
        if let proximityManagerIndex = self.proximityManagerIndex {
            DeviceProximityManager.shared().remove(proximityManagerIndex)
        }
        
        if let playbackItem = self.playbackItem {
            switch playbackItem {
                case .audio:
                    playbackItem.pause()
                case let .instantVideo(node):
                    node.setSoundEnabled(false)
                    self.overlayMediaManager.controller?.removeNode(node)
            }
        }
    }
    
    func control(_ action: SharedMediaPlayerControlAction) {
        switch action {
            case .next:
                self.scheduledPlaybackAction = .play
                self.playlist.control(.next)
            case .previous:
                let threshold: Double = 5.0
                if let playbackStateValue = self._playbackStateValue, case let .item(item) = playbackStateValue, item.status.duration > threshold, item.status.timestamp > threshold {
                    self.control(.seek(0.0))
                } else {
                    self.scheduledPlaybackAction = .play
                    self.playlist.control(.previous)
                }
            case let .playback(action):
                if let playbackItem = self.playbackItem {
                    switch action {
                        case .play:
                            playbackItem.play()
                        case .pause:
                            playbackItem.pause()
                        case .togglePlayPause:
                            playbackItem.togglePlayPause()
                    }
                } else {
                    self.scheduledPlaybackAction = action
                }
            case let .seek(timestamp):
                if let playbackItem = self.playbackItem {
                    playbackItem.seek(timestamp)
                }
            case let .setOrder(order):
                self.playlist.setOrder(order)
            case let .setLooping(looping):
                self.playlist.setLooping(looping)
            case let .setBaseRate(baseRate):
                self.playbackRate = baseRate
                if let playbackItem = self.playbackItem {
                    let rateValue: Double
                    switch baseRate {
                        case .x1:
                            rateValue = 1.0
                        case .x2:
                            rateValue = 1.8
                    }
                    switch playbackItem {
                        case let .audio(player):
                            player.setBaseRate(rateValue)
                        
                        case let .instantVideo(node):
                            node.setBaseRate(rateValue)
                    }
                }
        }
    }
    
    func stop() {
        if let playbackItem = self.playbackItem {
            switch playbackItem {
                case let .audio(player):
                    player.pause()
                case let .instantVideo(node):
                    node.setSoundEnabled(false)
            }
        }
    }
    
    private func updatePrefetchItems(item: SharedMediaPlaylistItem?, previousItem: SharedMediaPlaylistItem?, nextItem: SharedMediaPlaylistItem?, ordering: MusicPlaybackSettingsOrder) {
        var prefetchItems: (SharedMediaPlaybackDataSource, SharedMediaPlaybackDataSource)?
        if let playbackData = item?.playbackData {
            switch ordering {
                case .regular:
                    if let previousItem = previousItem?.playbackData {
                        prefetchItems = (playbackData.source, previousItem.source)
                    }
                case .reversed:
                    if let nextItem = nextItem?.playbackData {
                        prefetchItems = (playbackData.source, nextItem.source)
                    }
                case .random:
                    break
            }
        }
        if self.currentPrefetchItems?.0 != prefetchItems?.0 || self.currentPrefetchItems?.1 != prefetchItems?.1 {
            self.currentPrefetchItems = prefetchItems
            if let (current, next) = prefetchItems {
                let fetchedCurrentSignal: Signal<Never, NoError>
                let fetchedNextSignal: Signal<Never, NoError>
                switch current {
                    case let .telegramFile(file):
                        fetchedCurrentSignal = self.account.postbox.mediaBox.resourceData(file.media.resource)
                        |> mapToSignal { data -> Signal<Void, NoError> in
                            if data.complete {
                                return .single(Void())
                            } else {
                                return .complete()
                            }
                        }
                        |> take(1)
                        |> ignoreValues
                }
                switch next {
                    case let .telegramFile(file):
                        fetchedNextSignal = fetchedMediaResource(postbox: self.account.postbox, reference: file.resourceReference(file.media.resource))
                        |> ignoreValues
                        |> `catch` { _ -> Signal<Never, NoError> in
                            return .complete()
                        }
                }
                self.prefetchDisposable.set((fetchedCurrentSignal |> then(fetchedNextSignal)).start())
            } else {
                self.prefetchDisposable.set(nil)
            }
        }
    }
}
