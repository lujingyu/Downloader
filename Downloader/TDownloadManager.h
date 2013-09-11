//
//  TDownloadManager.h
//  Downloader
//
//  Created by jingyu lu on 9/9/13.
//  Copyright (c) 2013 jingyu lu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Downloader.h"

extern NSString * const TDownloaderReceiveResponseNotification;
extern NSString * const TDownloaderReceiveDataNotification;
extern NSString * const TDownloaderFinishNotification;
extern NSString * const TDownloaderFailNotification;

extern NSString * const TDownloaderWillStartNotification;
extern NSString * const TDownloaderPauseNotification;




@interface TDownloadManager : NSObject {
	
	NSOperationQueue   *_downloadQueue;
}

+ (TDownloadManager *)sharedInstance;

- (void)addDownloadTask:(Downloader *)download;

@end
