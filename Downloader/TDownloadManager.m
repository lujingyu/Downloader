//
//  TDownloadManager.m
//  Downloader
//
//  Created by jingyu lu on 9/9/13.
//  Copyright (c) 2013 jingyu lu. All rights reserved.
//

#import "TDownloadManager.h"

#define QueueMaxConcurrentOperationCount 1

 NSString * const TDownloaderReceiveResponseNotification = @"downloader.receive.response";
 NSString * const TDownloaderReceiveDataNotification     = @"downloader.receive.data";
 NSString * const TDownloaderFinishNotification          = @"downloader.finish";
 NSString * const TDownloaderFailNotification            = @"downloader.fail";

 NSString * const TDownloaderWillStartTaskNotification  = @"downloader.will.start";
 NSString * const TDownloaderWillPauseTaskNotification  = @"downloader.will.pause";
 NSString * const TDownloaderWillCancelTaskNotification = @"downloader.will.cancel";
 NSString * const TDownloaderDidCancelTaskNotification  = @"downloader.did.cancel";

static TDownloadManager *instance = nil;

@implementation TDownloadManager

- (void)dealloc {
	[_downloadQueue release];
	[super dealloc];
}

+ (TDownloadManager *)sharedInstance {
	@synchronized(self) {
		if (instance == nil) {
			instance = [[self alloc] init];
		}
	}
	return instance;
}

- (id)init {
	if (self = [super init]) {
        [self addNotificationObserver];
		_downloadQueue = [[NSOperationQueue alloc] init];
		_downloadQueue.maxConcurrentOperationCount = QueueMaxConcurrentOperationCount;
	}
	return self;
}

- (void)postNotification:(NSString *)name object:(id)obj userInfo:(NSDictionary *)userInfo {
    [[NSNotificationCenter defaultCenter] postNotificationName:name object:obj userInfo:userInfo];
}

#pragma mark - notification callback

- (void)addNotificationObserver {
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserver:self selector:@selector(downloadDidReceiveResponse:) name:NotificationDownloadDidReceiveResponse object:nil];
	[center addObserver:self selector:@selector(downloadDidReceiveData:) name:NotificationDownloadDidReceiveData object:nil];
	[center addObserver:self selector:@selector(downloadDidFinish:) name:NotificationDownloadDidFinish object:nil];
	[center addObserver:self selector:@selector(downloadDidFail:) name:NotificationDownloadDidFail object:nil];
}

- (void)downloadDidReceiveResponse:(NSNotification *)notification {
    
    Downloader *downloader = [notification object];
    downloader.taskState = TaskStateWaiting;
    [self postNotification:TDownloaderReceiveResponseNotification object:downloader userInfo:[notification userInfo]];
}

- (void)downloadDidReceiveData:(NSNotification *)notification {
    
    Downloader *downloader = [notification object];
    if (downloader.taskState == TaskStatePausing || downloader.taskState == TaskStateCancelling) {
        
    }
    else {
        downloader.taskState = TaskStateDownloading;
    }
    [self postNotification:TDownloaderReceiveDataNotification object:downloader userInfo:[notification userInfo]];
}

- (void)downloadDidFinish:(NSNotification *)notification {
    
    Downloader *downloader = [notification object];
    
    if (downloader.taskState == TaskStatePausing) {
//        [downloader getReady];
    }
    else if (downloader.taskState == TaskStateCancelling) {
        [self postNotification:TDownloaderDidCancelTaskNotification object:downloader userInfo:[notification userInfo]];
    }
    [self postNotification:TDownloaderFinishNotification object:[notification object] userInfo:[notification userInfo]];
}

- (void)downloadDidFail:(NSNotification *)notification {
    
    Downloader *downloader = [notification object];

    if (downloader.taskState == TaskStatePausing) {
//        [downloader getReady];
    }
    else if (downloader.taskState == TaskStateCancelling) {
        [self postNotification:TDownloaderDidCancelTaskNotification object:downloader userInfo:[notification userInfo]];
    }
    [self postNotification:TDownloaderFailNotification object:downloader userInfo:[notification userInfo]];
}

#pragma mark - action

- (void)addDownloadTask:(Downloader *)download {
    
    download.taskState = TaskStateWaiting;
	NBLog(@"tasks count before adding: %d", [[_downloadQueue operations] count]);
	[_downloadQueue addOperation:download];
	NBLog(@"tasks count after adding: %d", [[_downloadQueue operations] count]);
    
    [self postNotification:TDownloaderWillStartTaskNotification object:download userInfo:nil];
}

- (void)resumeDownloadTask:(Downloader *)download {
    
    [download getReady];
    download.taskState = TaskStateWaiting;
	NBLog(@"tasks count before resuming: %d", [[_downloadQueue operations] count]);
	[_downloadQueue addOperation:download];
	NBLog(@"tasks count after resuming: %d", [[_downloadQueue operations] count]);
    
    [self postNotification:TDownloaderWillStartTaskNotification object:download userInfo:nil];
}

- (void)pauseDownloadTask:(Downloader *)download {
    // 逻辑:
    // 1. 首先应取消下载，然后还原至ready状态，这样在恢复的时候才可以重新添加到队列
    // 2. 接着设置taskstate为pause，这样可以让前端知道当前的状态
    // 解决思路: 由于Downloader不提供改变ready状态的外部接口，所以考虑以下两种解决方案
    // 方案1. 考虑重新初始化一个新的downloader进行深拷贝
    // 方案2. 为Downloader添加reset供外部调用的接口，待测试是否会影响其他逻辑判断
    
    download.taskState = TaskStatePausing;
    [download cancel];
    [self postNotification:TDownloaderWillPauseTaskNotification object:download userInfo:nil];
}


- (void)cancelDownloadTask:(Downloader *)download {
    
    download.taskState = TaskStateCancelling;
    [download cancel];
    [self postNotification:TDownloaderWillCancelTaskNotification object:download userInfo:nil];
}


@end
