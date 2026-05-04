//
//  SafePluginRegistrant.h
//  Runner
//
//  Registers the iOS plugins that this app actually uses.
//  Keep background_downloader out of AppDelegate startup: Gemma downloads are
//  handled by IOSModelDownloadManager, and background_downloader 9.5.4 crashes
//  during iOS plugin registration on the current iOS 18 device/debug toolchain.
//

#ifndef SafePluginRegistrant_h
#define SafePluginRegistrant_h

#import <Flutter/Flutter.h>

NS_ASSUME_NONNULL_BEGIN

@interface SafePluginRegistrant : NSObject
+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry;
@end

NS_ASSUME_NONNULL_END
#endif /* SafePluginRegistrant_h */
