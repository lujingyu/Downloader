//
//  TDownloadManager.h
//  Downloader
//
//  Created by jingyu lu on 9/9/13.
//  Copyright (c) 2013 jingyu lu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Book.h"

extern NSString * const TDownloaderReceiveResponseNotification;
extern NSString * const TDownloaderReceiveDataNotification;
extern NSString * const TDownloaderFinishNotification;
extern NSString * const TDownloaderFailNotification;

extern NSString * const TDownloaderWillStartTaskNotification;
extern NSString * const TDownloaderWillPauseTaskNotification;
extern NSString * const TDownloaderWillCancelTaskNotification;
extern NSString * const TDownloaderDidCancelTaskNotification;





@interface TDownloadManager : NSObject {
	
	NSOperationQueue      *_downloadQueue;
}

+ (TDownloadManager *)sharedInstance;

- (void)addDownloadTask:(Downloader *)download;
- (void)pauseDownloadTask:(Downloader *)download;
- (void)resumeDownloadTask:(Downloader *)download;
- (void)cancelDownloadTask:(Downloader *)download;

@end
