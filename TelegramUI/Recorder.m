//
//  Recorder.m
//  libtgvoip
//
//  Created by Daniyar Salakhutdinov on 28/01/2019.
//  Copyright © 2019 Grishka. All rights reserved.
//

#import "Recorder.h"
#import <AVFoundation/AVFoundation.h>

#define kRecorderProcessQueueName "com.zuev.telegram.recorder"

@interface Recorder () {
    int64_t _callId;
    NSString *_uuid;
    AVAudioFile *_input;
    AVAudioFile *_output;
    dispatch_queue_t _processQueue;
    BOOL _isStopping;
}

@end

@implementation Recorder

- (id)init {
    if (self = [super init]) {
        _processQueue = dispatch_queue_create(kRecorderProcessQueueName, DISPATCH_QUEUE_SERIAL);
        [self createRecordsFolderIfNotExists];
        [self removeChunksIfAny];
    }
    return self;
}

- (void)createRecordsFolderIfNotExists {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *folderPath = [self inputFolderPath];
    BOOL isDirectory = NO;
    if ([manager fileExistsAtPath:folderPath isDirectory:&isDirectory] && isDirectory) return;
    NSError *error = nil;
    [manager createDirectoryAtPath:folderPath withIntermediateDirectories:NO attributes:nil error:&error];
}

- (void)removeChunksIfAny {
    // removes all the input/output wav files
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *folderPath = [self inputFolderPath];
    NSArray<NSString *> *paths = [manager contentsOfDirectoryAtPath:folderPath error:nil];
    for (NSString *path in paths) {
        if (![path hasSuffix:@"put.wav"]) continue;
        NSString *fullPath = [folderPath stringByAppendingPathComponent:path];
        [manager removeItemAtPath:fullPath error:nil];
    }
}

+ (instancetype)sharedInstance {
    static Recorder *_instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instance = [[Recorder alloc] init];
    });
    return _instance;
}

#pragma mark recorder protocol

- (void)start:(int64_t)callId {
    if (_isRecording) return;
    _uuid = [[[NSUUID alloc] init] UUIDString];
    _callId = callId;
    // create files for input and output
    NSError *error = nil;
    NSDictionary<NSString *, id> *settings = [[self class] audioFormatSettings];
    
    NSURL *inputFileUrl = [self fileUrlForInput:YES];
    _input = [[AVAudioFile alloc] initForWriting:inputFileUrl settings:settings commonFormat:AVAudioPCMFormatInt16 interleaved:NO error:&error];
    if (error != nil) {
        NSLog(@"Could not create input file with error: %@", error.localizedDescription);
        return;
    }
    
    NSURL *outputFileUrl = [self fileUrlForInput:NO];
    _output = [[AVAudioFile alloc] initForWriting:outputFileUrl settings:settings commonFormat:AVAudioPCMFormatInt16 interleaved:NO error:&error];
    if (error != nil) {
        NSLog(@"Could not create output file with error: %@", error.localizedDescription);
        return;
    }
    
    _isRecording = YES;
}

- (nullable NSURL *)fileUrlForInput:(BOOL)input {
    NSString *suffix = input ? @"_input.wav" : @"_output.wav";
    return [self fileUrlWithSuffix:suffix];
}

- (nullable NSURL *)fileUrlWithSuffix:(NSString *)suffix {
    if (!_uuid) return nil;
    NSString *folderPath = [self inputFolderPath];
    NSString *filename = [NSString stringWithFormat:@"/%@%@", _uuid, suffix];
    NSString *path = [folderPath stringByAppendingString:filename];
    return [NSURL fileURLWithPath:path];
}

+ (nonnull NSDictionary<NSString *, id> *)audioFormatSettings {
    return @{AVFormatIDKey : @(kAudioFormatLinearPCM),
             AVSampleRateKey : @(48000),
             AVNumberOfChannelsKey : @(1),
             AVLinearPCMIsFloatKey : @(NO),
             AVLinearPCMBitDepthKey : @(16),
             AVLinearPCMIsBigEndianKey : @(NO),
             AVEncoderAudioQualityKey : @(AVAudioQualityMax)};
}

- (NSString *)inputFolderPath {
    return [NSFileManager recordingsFolderUrlPath];
}

- (void)stop {
    if (!_isRecording || _isStopping) return;
    _isStopping = YES;
    // save the files
    _input = nil;
    _output = nil;
    // combine in a file
    dispatch_async(_processQueue, ^{
        [self combineFilesWithCompletionHandler:^(NSURL * _Nullable url) {
            int64_t callId = _callId;
            // reset state
            _isStopping = NO;
            _isRecording = NO;
            _uuid = nil;
            _callId = 0;
            // call delegate method
            dispatch_async(dispatch_get_main_queue(), ^{
                if (url && self.delegate && [self.delegate respondsToSelector:@selector(recorder:didFinishRecordingCallWithId:withAudioFileNamed:)]) {
                    [self.delegate recorder:self didFinishRecordingCallWithId:callId withAudioFileNamed:url.lastPathComponent];
                }
            });
        }];
    });
}

- (void)combineFilesWithCompletionHandler:(void (^ _Nullable)(NSURL * _Nullable))handler {
    NSURL *inputUrl = [self fileUrlForInput:YES];
    NSURL *outputUrl = [self fileUrlForInput:NO];
    if (!inputUrl || !outputUrl) {
        [self flushAndCallHandler:handler result:nil];
        return;
    }
    
    AVURLAsset *input = [AVURLAsset URLAssetWithURL:inputUrl options:nil];
    CMTimeRange inputTimeRange = CMTimeRangeMake(kCMTimeZero, input.duration);
    AVURLAsset *output = [AVURLAsset URLAssetWithURL:outputUrl options:nil];
    CMTimeRange outputTimeRange = CMTimeRangeMake(kCMTimeZero, output.duration);
    if (!input || !output) {
        [self flushAndCallHandler:handler result:nil];
        return;
    }
    
    NSError *error = nil;
    
    AVMutableComposition *composition = [AVMutableComposition composition];
    AVMutableCompositionTrack *inputTrack = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
    AVMutableCompositionTrack *outputTrack = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
    [inputTrack insertTimeRange:inputTimeRange ofTrack:[[input tracksWithMediaType:AVMediaTypeAudio] firstObject] atTime:kCMTimeZero error:&error];
    if (error) {
        [self flushAndCallHandler:handler result:nil];
        return;
    }
    [outputTrack insertTimeRange:outputTimeRange ofTrack:[[output tracksWithMediaType:AVMediaTypeAudio] firstObject] atTime:kCMTimeZero error:&error];
    if (error) {
        [self flushAndCallHandler:handler result:nil];
        return;
    }
    
    AVAssetExportSession *session = [AVAssetExportSession exportSessionWithAsset:composition presetName:AVAssetExportPresetAppleM4A];
    NSString *suffix = [NSString stringWithFormat:@".m4a"];
    NSURL *sessionUrl = [self fileUrlWithSuffix:suffix];
    session.outputURL = sessionUrl;
    session.outputFileType = AVFileTypeAppleM4A;
    
    [session exportAsynchronouslyWithCompletionHandler:^{
        NSURL *result = (session.status == AVAssetExportSessionStatusCompleted) ? sessionUrl : nil;
        [self flushAndCallHandler:handler result:result];
    }];
}

- (void)flushAndCallHandler:(void (^ _Nullable)(NSURL * _Nullable))handler result:(NSURL * _Nullable)url  {
    [self removeChunksIfAny];
    if (handler)
        handler(url);
}

#pragma mark getters

- (BOOL)isRecording {
    return _isRecording;
}

#pragma mark recording

- (void)processInput:(void *)buffer ofLength:(size_t)length {
    if (!_isRecording) return;
    [self saveBuffer:buffer ofLength:length intoFile:_input];
}

- (void)processOutput:(void *)buffer ofLength:(size_t)length {
    if (!_isRecording) return;
    [self saveBuffer:buffer ofLength:length intoFile:_output];
}

- (void)saveBuffer:(void *)buffer ofLength:(size_t)length intoFile:(AVAudioFile *)file {
    if (!file) return;
    
    AVAudioFormat *format = [[AVAudioFormat alloc] initWithSettings:[[self class] audioFormatSettings]];
    UInt32 bytesPerFrame = format.streamDescription->mBytesPerFrame;
    
    AVAudioFrameCount capacity = (AVAudioFrameCount)length / bytesPerFrame;
    AVAudioPCMBuffer *pcmBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:capacity];
    pcmBuffer.frameLength = capacity;
    // copy bytes
    void *channelBuffer = pcmBuffer.int16ChannelData[0];
    if (!channelBuffer) return;
    memcpy(channelBuffer, buffer, length);
    // write to file
    dispatch_async(_processQueue, ^{
        NSError *error;
        [file writeFromBuffer:pcmBuffer error:&error];
        if (error != nil)
            NSLog(@"Could not write buffer of size %ld into file with error: %@", length, error.localizedDescription);
    });
}

@end

@implementation NSFileManager (RecrodersFolder)

+ (nonnull NSString *)recordingsFolderUrlPath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsFolder = [paths firstObject];
    return [documentsFolder stringByAppendingString:@"/records"];
}

@end
