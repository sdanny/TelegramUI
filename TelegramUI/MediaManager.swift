import Foundation
import SwiftSignalKit
import AVFoundation
import MobileCoreServices
import Postbox
import TelegramCore
import MediaPlayer

import TelegramUIPrivateModule

enum SharedMediaPlayerGroup: Int {
    case music = 0
    case voiceAndInstantVideo = 1
}

public enum MediaManagerPlayerType {
    case voice
    case music
}

private let sharedAudioSession: ManagedAudioSession = {
    let audioSession = ManagedAudioSession()
    let _ = (audioSession.headsetConnected() |> deliverOnMainQueue).start(next: { value in
        DeviceProximityManager.shared().setGloballyEnabled(!value)
    })
    return audioSession
}()

enum SharedMediaPlayerItemPlaybackStateOrLoading: Equatable {
    case state(SharedMediaPlayerItemPlaybackState)
    case loading
}

private struct GlobalControlOptions: OptionSet {
    var rawValue: Int32
    
    init(rawValue: Int32 = 0) {
        self.rawValue = rawValue
    }
    
    static let play = GlobalControlOptions(rawValue: 1 << 0)
    static let pause = GlobalControlOptions(rawValue: 1 << 1)
    static let previous = GlobalControlOptions(rawValue: 1 << 2)
    static let next = GlobalControlOptions(rawValue: 1 << 3)
    static let playPause = GlobalControlOptions(rawValue: 1 << 4)
    static let seek = GlobalControlOptions(rawValue: 1 << 5)
}

public final class MediaManager: NSObject {
    public static var globalAudioSession: ManagedAudioSession {
        return sharedAudioSession
    }
    
    private let isCurrentPromise = ValuePromise<Bool>(false)
    var isCurrent: Bool = false {
        didSet {
            if self.isCurrent != oldValue {
                self.isCurrentPromise.set(self.isCurrent)
            }
        }
    }
    
    private let queue = Queue.mainQueue()
    
    private let accountManager: AccountManager
    private let inForeground: Signal<Bool, NoError>
    
    public let audioSession: ManagedAudioSession
    public let overlayMediaManager = OverlayMediaManager()
    let sharedVideoContextManager = SharedVideoContextManager()
    
    private var nextPlayerIndex: Int32 = 0
    
    private var voiceMediaPlayer: SharedMediaPlayer? {
        didSet {
            if self.voiceMediaPlayer !== oldValue {
                if let voiceMediaPlayer = self.voiceMediaPlayer {
                    let account = voiceMediaPlayer.account
                    self.voiceMediaPlayerStateValue.set(voiceMediaPlayer.playbackState
                    |> map { state -> (Account, SharedMediaPlayerItemPlaybackStateOrLoading)? in
                        guard let state = state else {
                            return nil
                        }
                        if case let .item(item) = state {
                            return (account, .state(item))
                        } else {
                            return (account, .loading)
                        }
                    } |> deliverOnMainQueue)
                } else {
                    self.voiceMediaPlayerStateValue.set(.single(nil))
                }
            }
        }
    }
    private let voiceMediaPlayerStateValue = Promise<(Account, SharedMediaPlayerItemPlaybackStateOrLoading)?>(nil)
    var voiceMediaPlayerState: Signal<(Account, SharedMediaPlayerItemPlaybackStateOrLoading)?, NoError> {
        return self.voiceMediaPlayerStateValue.get()
    }
    
    private var musicMediaPlayer: SharedMediaPlayer? {
        didSet {
            if self.musicMediaPlayer !== oldValue {
                if let musicMediaPlayer = self.musicMediaPlayer {
                    let account = musicMediaPlayer.account
                    self.musicMediaPlayerStateValue.set(musicMediaPlayer.playbackState
                    |> map { state -> (Account, SharedMediaPlayerItemPlaybackStateOrLoading)? in
                        guard let state = state else {
                            return nil
                        }
                        if case let .item(item) = state {
                            return (account, .state(item))
                        } else {
                            return (account, .loading)
                        }
                    } |> deliverOnMainQueue)
                } else {
                    self.musicMediaPlayerStateValue.set(.single(nil))
                }
            }
        }
    }
    private let musicMediaPlayerStateValue = Promise<(Account, SharedMediaPlayerItemPlaybackStateOrLoading)?>(nil)
    var musicMediaPlayerState: Signal<(Account, SharedMediaPlayerItemPlaybackStateOrLoading)?, NoError> {
        return self.musicMediaPlayerStateValue.get()
    }
    
    private let globalMediaPlayerStateValue = Promise<(Account, SharedMediaPlayerItemPlaybackStateOrLoading, MediaManagerPlayerType)?>()
    var globalMediaPlayerState: Signal<(Account, SharedMediaPlayerItemPlaybackStateOrLoading, MediaManagerPlayerType)?, NoError> {
        return self.globalMediaPlayerStateValue.get()
    }
    public var activeGlobalMediaPlayerAccountId: Signal<AccountRecordId?, NoError> {
        return self.globalMediaPlayerStateValue.get()
        |> map { state in
            return state?.0.id
        }
        |> distinctUntilChanged
    }
    
    private let setPlaylistByTypeDisposables = DisposableDict<MediaManagerPlayerType>()
    
    private let sharedPlayerByGroup: [SharedMediaPlayerGroup: SharedMediaPlayer] = [:]
    private var currentOverlayVideoNode: OverlayMediaItemNode?
    
    private let globalControlsStatus = Promise<MediaPlayerStatus?>(nil)
    
    private let globalControlsDisposable = MetaDisposable()
    private let globalControlsArtworkDisposable = MetaDisposable()
    private let globalControlsArtwork = Promise<(Account, SharedMediaPlaybackAlbumArt)?>(nil)
    private let globalControlsStatusDisposable = MetaDisposable()
    private let globalAudioSessionForegroundDisposable = MetaDisposable()
    
    let universalVideoManager = UniversalVideoContentManager()
    
    let galleryHiddenMediaManager = GalleryHiddenMediaManager()
    
    init(accountManager: AccountManager, inForeground: Signal<Bool, NoError>) {
        self.accountManager = accountManager
        self.inForeground = inForeground
        
        self.audioSession = sharedAudioSession
        
        super.init()
       
        let combinedPlayersSignal: Signal<(Account, SharedMediaPlayerItemPlaybackStateOrLoading, MediaManagerPlayerType)?, NoError> = combineLatest(queue: Queue.mainQueue(), self.voiceMediaPlayerState, self.musicMediaPlayerState)
        |> map { voice, music -> (Account, SharedMediaPlayerItemPlaybackStateOrLoading, MediaManagerPlayerType)? in
            if let voice = voice {
                return (voice.0, voice.1, .voice)
            } else if let music = music {
                return (music.0, music.1, .music)
            } else {
                return nil
            }
        }
        self.globalMediaPlayerStateValue.set(combinedPlayersSignal
        |> distinctUntilChanged(isEqual: { lhs, rhs in
            return lhs?.0 === rhs?.0 && lhs?.1 == rhs?.1 && lhs?.2 == rhs?.2
        }))
        
        var baseNowPlayingInfo: [String: Any]?
        
        var previousState: SharedMediaPlayerItemPlaybackState?
        var previousDisplayData: SharedMediaPlaybackDisplayData?
        let globalControlsArtwork = self.globalControlsArtwork
        let globalControlsStatus = self.globalControlsStatus
        
        var currentGlobalControlsOptions = GlobalControlOptions()
        
        self.globalControlsDisposable.set((self.globalMediaPlayerState
        |> deliverOnMainQueue).start(next: { stateAndType in
            var updatedGlobalControlOptions = GlobalControlOptions()
            if let (_, stateOrLoading, type) = stateAndType, case let .state(state) = stateOrLoading {
                if type == .music {
                    updatedGlobalControlOptions.insert(.previous)
                    updatedGlobalControlOptions.insert(.next)
                    updatedGlobalControlOptions.insert(.seek)
                    switch state.status.status {
                        case .playing, .buffering(_, true):
                            updatedGlobalControlOptions.insert(.pause)
                        default:
                            updatedGlobalControlOptions.insert(.play)
                    }
                }
            }
            
            if let (account, stateOrLoading, type) = stateAndType, type == .music, case let .state(state) = stateOrLoading, let displayData = state.item.displayData {
                if previousDisplayData != displayData {
                    previousDisplayData = displayData
                    
                    var nowPlayingInfo: [String: Any] = [:]
                    
                    var artwork: SharedMediaPlaybackAlbumArt?
                    
                    switch displayData {
                        case let .music(title, performer, artworkValue):
                            artwork = artworkValue
                            
                            let titleText: String = title ?? "Unknown Track"
                            let subtitleText: String = performer ?? "Unknown Artist"
                            
                            nowPlayingInfo[MPMediaItemPropertyTitle] = titleText
                            nowPlayingInfo[MPMediaItemPropertyArtist] = subtitleText
                        case let .voice(author, _):
                            let titleText: String = author?.displayTitle ?? ""
                            
                            nowPlayingInfo[MPMediaItemPropertyTitle] = titleText
                        case let .instantVideo(author, _, _):
                            let titleText: String = author?.displayTitle ?? ""
                            
                            nowPlayingInfo[MPMediaItemPropertyTitle] = titleText
                    }
                    
                    globalControlsArtwork.set(.single(artwork.flatMap({ (account, $0) })))
                    
                    baseNowPlayingInfo = nowPlayingInfo
                    
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                }
                
                if previousState != state {
                    previousState = state
                    globalControlsStatus.set(.single(state.status))
                }
            } else {
                previousState = nil
                previousDisplayData = nil
                globalControlsStatus.set(.single(nil))
                globalControlsArtwork.set(.single(nil))
                
                if baseNowPlayingInfo != nil {
                    baseNowPlayingInfo = nil
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
                }
            }
            
            if currentGlobalControlsOptions != updatedGlobalControlOptions {
                let commandCenter = MPRemoteCommandCenter.shared()
                
                var optionsAndCommands: [(GlobalControlOptions, MPRemoteCommand, Selector)] = [
                    (.play, commandCenter.playCommand, #selector(self.playCommandEvent(_:))),
                    (.pause, commandCenter.pauseCommand, #selector(self.pauseCommandEvent(_:))),
                    (.previous, commandCenter.previousTrackCommand, #selector(self.previousTrackCommandEvent(_:))),
                    (.next, commandCenter.nextTrackCommand, #selector(self.nextTrackCommandEvent(_:))),
                    ([.play, .pause], commandCenter.togglePlayPauseCommand, #selector(self.togglePlayPauseCommandEvent(_:)))
                ]
                if #available(iOSApplicationExtension 9.1, *) {
                    optionsAndCommands.append((.seek, commandCenter.changePlaybackPositionCommand, #selector(self.changePlaybackPositionCommandEvent(_:))))
                }
                
                for (option, command, selector) in optionsAndCommands {
                    let previousValue = !currentGlobalControlsOptions.intersection(option).isEmpty
                    let updatedValue = !updatedGlobalControlOptions.intersection(option).isEmpty
                    if previousValue != updatedValue {
                        if updatedValue {
                            command.isEnabled = true
                            command.addTarget(self, action: selector)
                        } else {
                            command.isEnabled = false
                            command.removeTarget(self, action: selector)
                        }
                    }
                }
                
                currentGlobalControlsOptions = updatedGlobalControlOptions
            }
        }))
        
        self.globalControlsArtworkDisposable.set((self.globalControlsArtwork.get()
        |> distinctUntilChanged(isEqual: { $0?.0 === $1?.0 && $0?.1 == $1?.1 })
        |> mapToSignal { value -> Signal<UIImage?, NoError> in
            if let (account, value) = value {
                return Signal { subscriber in
                    let fetched = account.postbox.mediaBox.fetchedResource(value.fullSizeResource, parameters: nil).start()
                    let data = account.postbox.mediaBox.resourceData(value.fullSizeResource, pathExtension: nil, option: .complete(waitUntilFetchStatus: false)).start(next: { data in
                        if data.complete, let value = try? Data(contentsOf: URL(fileURLWithPath: data.path)) {
                            subscriber.putNext(UIImage(data: value))
                            subscriber.putCompletion()
                        }
                    })
                    return ActionDisposable {
                        fetched.dispose()
                        data.dispose()
                    }
                }
            } else {
                return .single(nil)
            }
        } |> deliverOnMainQueue).start(next: { image in
            if var nowPlayingInfo = baseNowPlayingInfo {
                if let image = image {
                    if #available(iOSApplicationExtension 10.0, *) {
                        nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size, requestHandler: { size in
                            return image
                        })
                    } else {
                        nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(image: image)
                    }
                } else {
                    nowPlayingInfo.removeValue(forKey: MPMediaItemPropertyArtwork)
                }
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                baseNowPlayingInfo = nowPlayingInfo
            }
        }))
        
        self.globalControlsStatusDisposable.set((self.globalControlsStatus.get()
        |> deliverOnMainQueue).start(next: { next in
            if let next = next {
                if var nowPlayingInfo = baseNowPlayingInfo {
                    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = next.duration as NSNumber
                    switch next.status {
                        case .playing:
                            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0 as NSNumber
                        case .buffering, .paused:
                            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 0.0 as NSNumber
                    }
                    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = next.timestamp as NSNumber
                    
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                }
            }
        }))
        
       
        let shouldKeepAudioSession: Signal<Bool, NoError> = combineLatest(queue: Queue.mainQueue(), self.globalMediaPlayerState, inForeground)
        |> map { stateAndType, inForeground -> Bool in
            var isPlaying = false
            if let (_, stateOrLoading, _) = stateAndType, case let .state(state) = stateOrLoading {
                switch state.status.status {
                    case .playing:
                        isPlaying = true
                    case let .buffering(_, whilePlaying):
                        isPlaying = whilePlaying
                    default:
                        break
                }
            }
            if !inForeground {
                if !isPlaying {
                    return true
                }
            }
            return false
        }
        |> distinctUntilChanged
        |> mapToSignal { value -> Signal<Bool, NoError> in
            if value {
                return .single(true) |> delay(0.8, queue: Queue.mainQueue())
            } else {
                return .single(false)
            }
        }
        
        self.globalAudioSessionForegroundDisposable.set((shouldKeepAudioSession |> deliverOnMainQueue).start(next: { [weak self] value in
            guard let strongSelf = self else {
                return
            }
            if strongSelf.isCurrent && value {
                strongSelf.audioSession.dropAll()
            }
        }))
    }
    
    deinit {
        self.globalControlsDisposable.dispose()
        self.globalControlsArtworkDisposable.dispose()
        self.globalControlsStatusDisposable.dispose()
        self.setPlaylistByTypeDisposables.dispose()
        self.globalAudioSessionForegroundDisposable.dispose()
    }
    
    func audioRecorder(beginWithTone: Bool, applicationBindings: TelegramApplicationBindings, beganWithTone: @escaping (Bool) -> Void) -> Signal<ManagedAudioRecorder?, NoError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            
            self.queue.async {
                let audioRecorder = ManagedAudioRecorder(mediaManager: self, pushIdleTimerExtension: { [weak applicationBindings] in
                    return applicationBindings?.pushIdleTimerExtension() ?? EmptyDisposable
                }, beginWithTone: beginWithTone, beganWithTone: beganWithTone)
                subscriber.putNext(audioRecorder)
                
                disposable.set(ActionDisposable {
                })
            }
            
            return disposable
        }
    }
    
    func setPlaylist(_ playlist: (Account, SharedMediaPlaylist)?, type: MediaManagerPlayerType) {
        assert(Queue.mainQueue().isCurrent())
        let inputData: Signal<(Account, SharedMediaPlaylist, MusicPlaybackSettings)?, NoError>
        if let (account, playlist) = playlist {
            inputData = self.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.musicPlaybackSettings])
            |> take(1)
            |> map { sharedData in
                let settings = (sharedData.entries[ApplicationSpecificSharedDataKeys.musicPlaybackSettings] as? MusicPlaybackSettings) ?? MusicPlaybackSettings.defaultSettings
                return (account, playlist, settings)
            }
        } else {
            inputData = .single(nil)
        }
        self.setPlaylistByTypeDisposables.set((inputData
        |> deliverOnMainQueue).start(next: { [weak self] inputData in
            if let strongSelf = self {
                let nextPlayerIndex = strongSelf.nextPlayerIndex
                strongSelf.nextPlayerIndex += 1
                switch type {
                    case .voice:
                        strongSelf.musicMediaPlayer?.control(.playback(.pause))
                        strongSelf.voiceMediaPlayer?.stop()
                        if let (account, playlist, settings) = inputData {
                            let voiceMediaPlayer = SharedMediaPlayer(mediaManager: strongSelf, inForeground: strongSelf.inForeground, account: account, audioSession: strongSelf.audioSession, overlayMediaManager: strongSelf.overlayMediaManager, playlist: playlist, initialOrder: .reversed, initialLooping: .none, initialPlaybackRate: settings.voicePlaybackRate, playerIndex: nextPlayerIndex, controlPlaybackWithProximity: true)
                            strongSelf.voiceMediaPlayer = voiceMediaPlayer
                            voiceMediaPlayer.playedToEnd = { [weak voiceMediaPlayer] in
                                if let strongSelf = self, let voiceMediaPlayer = voiceMediaPlayer, voiceMediaPlayer === strongSelf.voiceMediaPlayer {
                                    voiceMediaPlayer.stop()
                                    strongSelf.voiceMediaPlayer = nil
                                }
                            }
                            voiceMediaPlayer.cancelled = { [weak voiceMediaPlayer] in
                                if let strongSelf = self, let voiceMediaPlayer = voiceMediaPlayer, voiceMediaPlayer === strongSelf.voiceMediaPlayer {
                                    voiceMediaPlayer.stop()
                                    strongSelf.voiceMediaPlayer = nil
                                }
                            }
                            voiceMediaPlayer.control(.playback(.play))
                        } else {
                            strongSelf.voiceMediaPlayer = nil
                        }
                    case .music:
                        strongSelf.musicMediaPlayer?.stop()
                        strongSelf.voiceMediaPlayer?.control(.playback(.pause))
                        if let (account, playlist, settings) = inputData {
                            let musicMediaPlayer = SharedMediaPlayer(mediaManager: strongSelf, inForeground: strongSelf.inForeground, account: account, audioSession: strongSelf.audioSession, overlayMediaManager: strongSelf.overlayMediaManager, playlist: playlist, initialOrder: settings.order, initialLooping: settings.looping, initialPlaybackRate: .x1, playerIndex: nextPlayerIndex, controlPlaybackWithProximity: false)
                            strongSelf.musicMediaPlayer = musicMediaPlayer
                            musicMediaPlayer.cancelled = { [weak musicMediaPlayer] in
                                if let strongSelf = self, let musicMediaPlayer = musicMediaPlayer, musicMediaPlayer === strongSelf.musicMediaPlayer {
                                    musicMediaPlayer.stop()
                                    strongSelf.musicMediaPlayer = nil
                                }
                            }
                            strongSelf.musicMediaPlayer?.control(.playback(.play))
                        } else {
                            strongSelf.musicMediaPlayer = nil
                        }
                }
            }
        }), forKey: type)
    }
    
    func playlistControl(_ control: SharedMediaPlayerControlAction, type: MediaManagerPlayerType? = nil) {
        assert(Queue.mainQueue().isCurrent())
        let selectedType: MediaManagerPlayerType
        if let type = type {
            selectedType = type
        } else if self.voiceMediaPlayer != nil {
            selectedType = .voice
        } else {
            selectedType = .music
        }
        switch selectedType {
            case .voice:
                self.voiceMediaPlayer?.control(control)
            case .music:
                if self.voiceMediaPlayer != nil {
                    switch control {
                        case .playback(.play), .playback(.togglePlayPause):
                            self.setPlaylist(nil, type: .voice)
                        default:
                            break
                    }
                }
                self.musicMediaPlayer?.control(control)
        }
    }
    
    func filteredPlaylistState(accountId: AccountRecordId, playlistId: SharedMediaPlaylistId, itemId: SharedMediaPlaylistItemId, type: MediaManagerPlayerType) -> Signal<SharedMediaPlayerItemPlaybackState?, NoError> {
        let signal: Signal<(Account, SharedMediaPlayerItemPlaybackStateOrLoading)?, NoError>
        switch type {
            case .voice:
                signal = self.voiceMediaPlayerState
            case .music:
                signal = self.musicMediaPlayerState
        }
        return signal
        |> map { stateOrLoading -> SharedMediaPlayerItemPlaybackState? in
            if let (account, stateOrLoading) = stateOrLoading, account.id == accountId, case let .state(state) = stateOrLoading {
                if state.playlistId.isEqual(to: playlistId) && state.item.id.isEqual(to: itemId) {
                    return state
                }
            }
            return nil
        } |> distinctUntilChanged(isEqual: { lhs, rhs in
            return lhs == rhs
        })
    }
    
    @objc func playCommandEvent(_ command: AnyObject) {
        self.playlistControl(.playback(.play))
    }
    
    @objc func pauseCommandEvent(_ command: AnyObject) {
        self.playlistControl(.playback(.pause))
    }
    
    @objc func previousTrackCommandEvent(_ command: AnyObject) {
        self.playlistControl(.previous)
    }
    
    @objc func nextTrackCommandEvent(_ command: AnyObject) {
        self.playlistControl(.next)
    }
    
    @objc func togglePlayPauseCommandEvent(_ command: AnyObject) {
        self.playlistControl(.playback(.togglePlayPause))
    }
    
    @objc func changePlaybackPositionCommandEvent(_ event: MPChangePlaybackPositionCommandEvent) {
        self.playlistControl(.seek(event.positionTime))
    }
    
    func setOverlayVideoNode(_ node: OverlayMediaItemNode?) {
        if let currentOverlayVideoNode = self.currentOverlayVideoNode {
            self.overlayMediaManager.controller?.removeNode(currentOverlayVideoNode, customTransition: true)
            self.currentOverlayVideoNode = nil
        }
        
        if let node = node {
            self.currentOverlayVideoNode = node
            self.overlayMediaManager.controller?.addNode(node, customTransition: true)
        }
    }
}
