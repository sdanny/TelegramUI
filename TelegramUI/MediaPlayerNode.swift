import Foundation
import UIKit
import AsyncDisplayKit
import SwiftSignalKit
import AVFoundation

private final class MediaPlayerNodeLayerNullAction: NSObject, CAAction {
    @objc func run(forKey event: String, object anObject: Any, arguments dict: [AnyHashable : Any]?) {
    }
}

private final class MediaPlayerNodeLayer: AVSampleBufferDisplayLayer {
    override func action(forKey event: String) -> CAAction? {
        return MediaPlayerNodeLayerNullAction()
    }
}

private final class MediaPlayerNodeDisplayNode: ASDisplayNode {
    var updateInHierarchy: ((Bool) -> Void)?
    
    override init() {
        super.init()
        self.isLayerBacked = true
    }
    
    override func willEnterHierarchy() {
        super.willEnterHierarchy()
        
        self.updateInHierarchy?(true)
    }
    
    override func didExitHierarchy() {
        super.didExitHierarchy()
        
        self.updateInHierarchy?(false)
    }
}

private enum PollStatus: CustomStringConvertible {
    case delay(Double)
    case finished
    
    var description: String {
        switch self {
            case let .delay(value):
                return "delay(\(value))"
            case .finished:
                return "finished"
        }
    }
}

final class MediaPlayerNode: ASDisplayNode {
    var videoInHierarchy: Bool = false
    var updateVideoInHierarchy: ((Bool) -> Void)?
    
    private var videoNode: MediaPlayerNodeDisplayNode
    
    private var videoLayer: AVSampleBufferDisplayLayer?
    
    private let videoQueue: Queue
    
    var snapshotNode: ASDisplayNode? {
        didSet {
            if let snapshotNode = oldValue {
                snapshotNode.removeFromSupernode()
            }
            
            if let snapshotNode = self.snapshotNode {
                snapshotNode.frame = self.bounds
                self.insertSubnode(snapshotNode, at: 0)
            }
        }
    }
    
    var takeFrameAndQueue: (Queue, () -> MediaTrackFrameResult)?
    var timer: SwiftSignalKit.Timer?
    var polling = false
    
    var currentRotationAngle = 0.0
    var currentAspect = 1.0
    
    var state: (timebase: CMTimebase, requestFrames: Bool, rotationAngle: Double, aspect: Double)? {
        didSet {
            self.updateState()
        }
    }
    
    private func updateState() {
        if let (timebase, requestFrames, rotationAngle, aspect) = self.state {
            if let videoLayer = self.videoLayer {
                videoQueue.async {
                    if videoLayer.controlTimebase !== timebase || videoLayer.status == .failed {
                        videoLayer.flush()
                        videoLayer.controlTimebase = timebase
                    }
                }
                
                if !self.currentRotationAngle.isEqual(to: rotationAngle) || !self.currentAspect.isEqual(to: aspect) {
                    self.currentRotationAngle = rotationAngle
                    self.currentAspect = aspect
                    var transform = CGAffineTransform(rotationAngle: CGFloat(rotationAngle))
                    if !rotationAngle.isZero {
                        transform = transform.scaledBy(x: CGFloat(aspect), y: CGFloat(1.0 / aspect))
                    }
                    videoLayer.setAffineTransform(transform)
                }
                
                if self.videoInHierarchy {
                    if requestFrames {
                        self.startPolling()
                    }
                }
            }
        }
    }
    
    private func startPolling() {
        if !self.polling {
            self.polling = true
            self.poll(completion: { [weak self] status in
                self?.polling = false
                
                if let strongSelf = self, let (_, requestFrames, _, _) = strongSelf.state, requestFrames {
                    strongSelf.timer?.invalidate()
                    switch status {
                        case let .delay(delay):
                            strongSelf.timer = SwiftSignalKit.Timer(timeout: delay, repeat: true, completion: {
                                if let strongSelf = self, let videoLayer = strongSelf.videoLayer, let (_, requestFrames, _, _) = strongSelf.state, requestFrames, strongSelf.videoInHierarchy {
                                    if videoLayer.isReadyForMoreMediaData {
                                        strongSelf.timer?.invalidate()
                                        strongSelf.timer = nil
                                        strongSelf.startPolling()
                                    }
                                }
                            }, queue: Queue.mainQueue())
                            strongSelf.timer?.start()
                        case .finished:
                            break
                    }
                }
            })
        }
    }
    
    private func poll(completion: @escaping (PollStatus) -> Void) {
        if let (takeFrameQueue, takeFrame) = self.takeFrameAndQueue, let videoLayer = self.videoLayer, let (timebase, _, _, _) = self.state {
            let layerRef = Unmanaged.passRetained(videoLayer)
            takeFrameQueue.async {
                let status: PollStatus
                do {
                    var numFrames = 0
                    let layer = layerRef.takeUnretainedValue()
                    let layerTime = CMTimeGetSeconds(CMTimebaseGetTime(timebase))
                    let rate = CMTimebaseGetRate(timebase)
                    var maxTakenTime = layerTime + 0.1
                    var finised = false
                    loop: while true {
                        let isReady = layer.isReadyForMoreMediaData
                        #if DEBUG
                        if let error = layer.error {
                            print("MediaPlayerNode error: \(error)")
                        }
                        #endif
                        
                        if isReady {
                            switch takeFrame() {
                                case let .restoreState(frames, atTime):
                                    layer.flush()
                                    for i in 0 ..< frames.count {
                                        let frame = frames[i]
                                        let frameTime = CMTimeGetSeconds(frame.position)
                                        maxTakenTime = frameTime
                                        let attachments = CMSampleBufferGetSampleAttachmentsArray(frame.sampleBuffer, true)! as NSArray
                                        let dict = attachments[0] as! NSMutableDictionary
                                        if i == 0 {
                                            CMSetAttachment(frame.sampleBuffer, kCMSampleBufferAttachmentKey_ResetDecoderBeforeDecoding as NSString, kCFBooleanTrue as AnyObject, kCMAttachmentMode_ShouldPropagate)
                                            CMSetAttachment(frame.sampleBuffer, kCMSampleBufferAttachmentKey_EndsPreviousSampleDuration as NSString, kCFBooleanTrue as AnyObject, kCMAttachmentMode_ShouldPropagate)
                                        }
                                        if CMTimeCompare(frame.position, atTime) < 0 {
                                            dict.setValue(kCFBooleanTrue as AnyObject, forKey: kCMSampleAttachmentKey_DoNotDisplay as NSString as String)
                                        } else if CMTimeCompare(frame.position, atTime) == 0 {
                                            dict.setValue(kCFBooleanTrue as AnyObject, forKey: kCMSampleAttachmentKey_DisplayImmediately as NSString as String)
                                            dict.setValue(kCFBooleanTrue as AnyObject, forKey: kCMSampleBufferAttachmentKey_EndsPreviousSampleDuration as NSString as String)
                                            //print("restore state to \(frame.position) -> \(frameTime) at \(layerTime) (\(i + 1) of \(frames.count))")
                                        }
                                        layer.enqueue(frame.sampleBuffer)
                                    }
                                case let .frame(frame):
                                    numFrames += 1
                                    let frameTime = CMTimeGetSeconds(frame.position)
                                    if rate.isZero {
                                        //print("enqueue \(frameTime) at \(layerTime)")
                                    }
                                    if frame.resetDecoder {
                                        layer.flush()
                                    }
                                    
                                    if frame.decoded && frameTime < layerTime {
                                        //print("drop frame at \(frameTime) current \(layerTime)")
                                        continue loop
                                    }
                                    
                                    //print("took frame at \(frameTime) current \(layerTime)")
                                    maxTakenTime = frameTime
                                    layer.enqueue(frame.sampleBuffer)
                                case .skipFrame:
                                    break
                                case .noFrames:
                                    finised = true
                                    break loop
                                case .finished:
                                    finised = true
                                    break loop
                            }
                        } else {
                            break loop
                        }
                    }
                    if finised {
                        status = .finished
                    } else {
                        status = .delay(max(1.0 / 30.0, maxTakenTime - layerTime))
                    }
                    //print("took \(numFrames) frames, status \(status)")
                }
                DispatchQueue.main.async {
                    layerRef.release()
                    
                    completion(status)
                }
            }
        }
    }
    
    var transformArguments: TransformImageArguments? {
        didSet {
            var cornerRadius: CGFloat = 0.0
            if let transformArguments = self.transformArguments {
                cornerRadius = transformArguments.corners.bottomLeft.radius
            }
            if !self.cornerRadius.isEqual(to: cornerRadius) {
                self.cornerRadius = cornerRadius
                self.clipsToBounds = !cornerRadius.isZero
            } else {
                if let transformArguments = self.transformArguments {
                    self.clipsToBounds = !cornerRadius.isZero || (transformArguments.imageSize.width > transformArguments.boundingSize.width || transformArguments.imageSize.height > transformArguments.boundingSize.height)
                }
            }
            self.updateLayout()
        }
    }
    
    init(backgroundThread: Bool = false) {
        self.videoNode = MediaPlayerNodeDisplayNode()
        
        if false && backgroundThread {
            self.videoQueue = Queue()
        } else {
            self.videoQueue = Queue.mainQueue()
        }
        
        super.init()
        
        self.videoNode.updateInHierarchy = { [weak self] value in
            if let strongSelf = self {
                if strongSelf.videoInHierarchy != value {
                    strongSelf.videoInHierarchy = value
                    if value {
                        strongSelf.updateState()
                    }
                }
                strongSelf.updateVideoInHierarchy?(value)
            }
        }
        self.addSubnode(self.videoNode)
        
        self.videoQueue.async { [weak self] in
            let videoLayer = MediaPlayerNodeLayer()
            videoLayer.videoGravity = .resize
            Queue.mainQueue().async {
                if let strongSelf = self {
                    strongSelf.videoLayer = videoLayer
                    strongSelf.updateLayout()
                    
                    strongSelf.layer.addSublayer(videoLayer)
                    strongSelf.updateState()
                }
            }
        }
    }
    
    deinit {
        assert(Queue.mainQueue().isCurrent())
        self.videoLayer?.removeFromSuperlayer()
        
        if let (takeFrameQueue, _) = self.takeFrameAndQueue {
            if let videoLayer = self.videoLayer {
                takeFrameQueue.async {
                    videoLayer.flushAndRemoveImage()
                    
                    takeFrameQueue.after(1.0, {
                        videoLayer.flushAndRemoveImage()
                    })
                }
            }
        }
    }
    
    override var frame: CGRect {
        didSet {
            if !oldValue.size.equalTo(self.frame.size) {
                self.updateLayout()
            }
        }
    }
    
    private func updateLayout() {
        let bounds = self.bounds
        
        let fittedRect: CGRect
        if let arguments = self.transformArguments {
            let drawingRect = bounds
            var fittedSize = arguments.imageSize
            if abs(fittedSize.width - bounds.size.width).isLessThanOrEqualTo(CGFloat(1.0)) {
                fittedSize.width = bounds.size.width
            }
            if abs(fittedSize.height - bounds.size.height).isLessThanOrEqualTo(CGFloat(1.0)) {
                fittedSize.height = bounds.size.height
            }
            
            fittedRect = CGRect(origin: CGPoint(x: drawingRect.origin.x + (drawingRect.size.width - fittedSize.width) / 2.0, y: drawingRect.origin.y + (drawingRect.size.height - fittedSize.height) / 2.0), size: fittedSize)
        } else {
            fittedRect = bounds
        }
        
        if let videoLayer = self.videoLayer {
            videoLayer.position = CGPoint(x: fittedRect.midX, y: fittedRect.midY)
            videoLayer.bounds = CGRect(origin: CGPoint(), size: fittedRect.size)
        }
        self.snapshotNode?.frame = fittedRect
    }
    
    func reset() {
        self.videoLayer?.flush()
    }
}
