//
//  Recorder.h
//  libtgvoip
//
//  Created by Daniyar Salakhutdinov on 28/01/2019.
//  Copyright © 2019 Grishka. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol RecorderProtocol <NSObject>

@property (nonatomic, readonly) BOOL isRecording;

- (void)start;
- (void)stopWithCompletionHandler:(void (^ _Nullable)(NSURL * _Nullable))handler save:(BOOL)save;

@end

@interface Recorder : NSObject <RecorderProtocol> {
    BOOL _isRecording;
}

@property (nonatomic, readonly) BOOL isRecording;

- (void)start;
- (void)stopWithCompletionHandler:(void (^ _Nullable)(NSURL * _Nullable))handler save:(BOOL)save;

- (nullable NSString *)inputFolderPath;

+ (nonnull instancetype)sharedInstance;

#pragma mark recording

- (void)processInput:(void *)buffer ofLength:(size_t)length;
- (void)processOutput:(void *)buffer ofLength:(size_t)length;

@end
