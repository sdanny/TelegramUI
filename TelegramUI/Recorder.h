//
//  Recorder.h
//  libtgvoip
//
//  Created by Daniyar Salakhutdinov on 28/01/2019.
//  Copyright © 2019 Grishka. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol RecorderProtocol;
@protocol RecorderDelegate <NSObject>

- (void)recorder:(id<RecorderProtocol> _Nonnull)recorder didFinishRecordingCallWithId:(int64_t)callId withAudioFileNamed:(NSString * _Nonnull)name;

@end

@protocol RecorderProtocol <NSObject>

@property (nonatomic, weak) id<RecorderDelegate> _Nullable delegate;
@property (nonatomic, readonly) BOOL isRecording;

- (void)start:(int64_t)callId;
- (void)stop;

@end

@interface Recorder : NSObject <RecorderProtocol> {
    BOOL _isRecording;
}

@property (nonatomic, weak) id<RecorderDelegate> _Nullable delegate;
@property (nonatomic, readonly) BOOL isRecording;

- (void)start:(int64_t)callId;
- (void)stop;

- (nullable NSString *)inputFolderPath;

+ (nonnull instancetype)sharedInstance;

#pragma mark recording

- (void)processInput:(void * _Nonnull)buffer ofLength:(size_t)length;
- (void)processOutput:(void * _Nonnull)buffer ofLength:(size_t)length;

@end

@interface NSFileManager (RecrodersFolder)

+ (nonnull NSString *)recordingsFolderUrlPath;

@end
