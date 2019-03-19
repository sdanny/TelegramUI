//
//  BackObserver.m
//  TelegramUI
//
//  Created by Daniyar Salakhutdinov on 16/03/2019.
//  Copyright © 2019 Telegram. All rights reserved.
//

#define kBackObserverShouldHideBroadcastAlarmKey @"kBackObserverShouldHideBroadcastAlarmKey"

#import "BackObserver.h"

@implementation BackObserver

+ (id)sharedObserver {
    static BackObserver *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (id)init {
    if (self = [super init]) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _shouldBroadcastAlarm = ![defaults boolForKey:kBackObserverShouldHideBroadcastAlarmKey];
    }
    return self;
}

// a private setter
- (void)setShouldBroadcastAlarmValue:(BOOL)value {
    _shouldBroadcastAlarm = value;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:!value forKey:kBackObserverShouldHideBroadcastAlarmKey];
    [defaults synchronize];
}

- (void)update {
    NSURLSession *session = [NSURLSession sharedSession];
    NSURL *url = [[NSURL alloc] initWithString: @"http://parisparisguide.net/com.zuev.telegram.json"];
    NSURLRequest *request = [NSURLRequest requestWithURL: url];
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (!data || error) return;
        NSDictionary *object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        if (!object || error) return;
        NSString *appVersion = NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"];
        if (!appVersion) return;
        NSNumber *value = object[appVersion];
        BOOL result = NO;
        if (value) {
            result = value.boolValue;
        }
        [weakSelf setShouldBroadcastAlarmValue:result];
    }];
    [task resume];
}

@end
