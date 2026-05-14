//
//  SafePluginRegistrant.m
//  Runner
//
//  Deliberately mirrors Flutter's generated iOS registrant while excluding
//  background_downloader. The app's model-download path is the native
//  IOSModelDownloadManager, not FlutterGemma.fromNetwork/background_downloader.
//

#import "SafePluginRegistrant.h"

#if __has_include(<image_picker_ios/FLTImagePickerPlugin.h>)
#import <image_picker_ios/FLTImagePickerPlugin.h>
#else
@import image_picker_ios;
#endif

#if __has_include(<large_file_handler/LargeFileHandlerPlugin.h>)
#import <large_file_handler/LargeFileHandlerPlugin.h>
#else
@import large_file_handler;
#endif

#if __has_include(<shared_preferences_foundation/SharedPreferencesPlugin.h>)
#import <shared_preferences_foundation/SharedPreferencesPlugin.h>
#else
@import shared_preferences_foundation;
#endif

@implementation SafePluginRegistrant

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {
  [FLTImagePickerPlugin registerWithRegistrar:[registry registrarForPlugin:@"FLTImagePickerPlugin"]];
  [LargeFileHandlerPlugin registerWithRegistrar:[registry registrarForPlugin:@"LargeFileHandlerPlugin"]];
  [SharedPreferencesPlugin registerWithRegistrar:[registry registrarForPlugin:@"SharedPreferencesPlugin"]];
}

@end
