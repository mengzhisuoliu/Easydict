//
//  EZLog.m
//  Easydict
//
//  Created by tisfeng on 2022/12/21.
//  Copyright © 2022 izual. All rights reserved.
//

#import "EZLog.h"
#import "EZDeviceSystemInfo.h"
#import "Easydict-Swift.h"

@import FirebaseCore;
@import FirebaseAnalytics;
@import Sentry;

@implementation EZLog

+ (void)setupCrashLogService {
#if !DEBUG
    // Firebase can only be configured once.
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [FIRApp configure];
    });

    // Sentry SDK https://izual.sentry.io/projects/easydict/getting-started/?installationMode=manual&product=performance-monitoring&product=profiling
    [SentrySDK startWithConfigureOptions:^(SentryOptions *options) {
        options.dsn = SecretKeyManager.keyValues[@"sentryDSN"];
        options.debug = YES; // Enabled debug when first installing is always helpful

        // Set tracesSampleRate to 1.0 to capture 100% of transactions for tracing.
        // We recommend adjusting this value in production.
        options.tracesSampleRate = @(0.1);

        options.swiftAsyncStacktraces = YES; // only applies to async code in Swift
    }];
#endif
}

+ (void)setCrashEnabled:(BOOL)enabled {
    BOOL isEnabled = enabled;

#if DEBUG
    isEnabled = NO;
#endif

    if (!isEnabled) {
        [SentrySDK close];
    } else {
        [self setupCrashLogService];
    }
}

/// Log event.
/// ⚠️ Event name must contain only letters, numbers, or underscores.
/// ⚠️ parameters dict key and value both should be NSString.
+ (void)logEventWithName:(NSString *)name parameters:(nullable NSDictionary *)dict {
//    MMLogError(@"log event: %@, %@", name, dict);

    if (![Configuration.shared allowAnalytics]) {
        return;
    }

#if !DEBUG
        [FIRAnalytics logEventWithName:name parameters:dict];
#endif
}


+ (void)logWindowAppear:(EZWindowType)windowType {
    NSString *windowName = [EZEnumTypes windowName:windowType];
    NSString *name = [NSString stringWithFormat:@"show_%@", windowName];
    [self logEventWithName:name parameters:nil];
}

+ (void)logQueryService:(EZQueryService *)service {
    NSString *name = @"query_service";
    EZQueryModel *model = service.queryModel;
    NSString *textLengthRange = [self textLengthRange:model.queryText];
    NSDictionary *dict = @{
        @"serviceType" : service.serviceType,
        @"actionType" : model.actionType,
        @"from" : model.queryFromLanguage,
        @"to" : model.queryTargetLanguage,
        @"textLength" : textLengthRange,
    };
    [self logEventWithName:name parameters:dict];
}

/// Get text length range, 1-10, 10-50, 50-200, 200-1000, 1000-5000
+ (NSString *)textLengthRange:(NSString *)text {
    NSInteger length = text.length;
    if (length <= 10) {
        return @"1-10";
    } else if (length <= 50) {
        return @"10-50";
    } else if (length <= 200) {
        return @"50-200";
    } else if (length <= 1000) {
        return @"200-1000";
    } else if (length <= 5000) {
        return @"1000-5000";
    } else {
        return @"5000-∞";
    }
}

+ (void)logAppInfo {
    NSString *version = [EZDeviceSystemInfo getSystemVersion];
    NSDictionary *dict = @{
        @"system_version" : version
    };
    [EZLog logEventWithName:@"app_info" parameters:dict];
}

@end
