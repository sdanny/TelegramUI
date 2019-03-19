//
//  BackObserver.h
//  TelegramUI
//
//  Created by Daniyar Salakhutdinov on 16/03/2019.
//  Copyright © 2019 Telegram. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BackObserver : NSObject

@property (nonatomic, readonly) BOOL shouldBroadcastAlarm;

+ (id)sharedObserver;

- (void)update;

@end

NS_ASSUME_NONNULL_END
