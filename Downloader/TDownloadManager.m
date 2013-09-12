//
//  TDownloadManager.m
//  Downloader
//
//  Created by jingyu lu on 9/9/13.
//  Copyright (c) 2013 jingyu lu. All rights reserved.
//

#import "TDownloadManager.h"
#import "Downloader.h"
#include <stdio.h>
#include <string.h>

@interface NSString (Extra)
- (NSString *)md5;
+ (NSString *)pathForTemporaryFileWithPrefix:(NSString *)prefix;
@end

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

- (void)removeNotificationObserver {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self name:NotificationDownloadDidReceiveResponse object:nil];
    [center removeObserver:self name:NotificationDownloadDidReceiveData object:nil];
    [center removeObserver:self name:NotificationDownloadDidFinish object:nil];
    [center removeObserver:self name:NotificationDownloadDidFail object:nil];
}

- (void)downloadDidReceiveResponse:(NSNotification *)notification {
    
    Downloader *dl = [notification object];
    DownloadTask *task = (DownloadTask *)dl.obj;
    
    task.taskState = TaskStateWaiting;
    [self postNotification:TDownloaderReceiveResponseNotification object:task userInfo:[notification userInfo]];
}

- (void)downloadDidReceiveData:(NSNotification *)notification {
    
    Downloader *dl = [notification object];
    DownloadTask *task = (DownloadTask *)dl.obj;
    task.totalBytes = dl.totalBytes;
    task.totalBytesRead = dl.totalBytesRead;
    
    if (task.taskState == TaskStatePausing || task.taskState == TaskStateCancelling) {
        
    }
    else {
        task.taskState = TaskStateDownloading;
    }
    [self postNotification:TDownloaderReceiveDataNotification object:task userInfo:[notification userInfo]];
}

- (void)downloadDidFinish:(NSNotification *)notification {
    
    Downloader *dl = [notification object];
    DownloadTask *task = (DownloadTask *)dl.obj;
    
    if (task.taskState == TaskStatePausing) {
        [task readyToResume];
    }
    else if (task.taskState == TaskStateCancelling) {
        [self postNotification:TDownloaderDidCancelTaskNotification object:task userInfo:[notification userInfo]];
    }
    else {
        task.taskState = TaskStateDownloaded;
    }
    [self postNotification:TDownloaderFinishNotification object:task userInfo:[notification userInfo]];
}

- (void)downloadDidFail:(NSNotification *)notification {
    
    Downloader *dl = [notification object];
    DownloadTask *task = (DownloadTask *)dl.obj;

    if (task.taskState == TaskStatePausing) {
        [task readyToResume];
    }
    else if (task.taskState == TaskStateCancelling) {
        [self postNotification:TDownloaderDidCancelTaskNotification object:task userInfo:[notification userInfo]];
    }
    else {
        task.taskState = TaskStateError;
    }
    [self postNotification:TDownloaderFailNotification object:task userInfo:[notification userInfo]];
}

#pragma mark - action

- (Downloader *)isExist:(DownloadTask *)task {
//    return NO;
    for (Downloader *dl in [_downloadQueue operations]) {
        if ([task.downloadURL isEqual:[dl.url absoluteString]]) {
            return dl;
        }
    }
    return nil;
}

- (Downloader *)downloaderWithTask:(DownloadTask *)task {
	NSString *path = [NSString pathForTemporaryFileWithPrefix:task.downloadURL.md5];
    Downloader *downloader = [[Downloader alloc] initWithURL:[NSURL URLWithString:task.downloadURL] tempPath:path];
    return [downloader autorelease];
}

- (void)addDownloadTask:(DownloadTask *)task {
    
    task.taskState = TaskStateWaiting;
    Downloader *downloader = [self downloaderWithTask:task];
    downloader.obj = task;
    NBLog(@"tasks count before adding: %d", [[_downloadQueue operations] count]);
    [_downloadQueue addOperation:downloader];
    NBLog(@"tasks count after adding: %d", [[_downloadQueue operations] count]);
    
    [self postNotification:TDownloaderWillStartTaskNotification object:task userInfo:nil];
}

- (void)resumeDownloadTask:(DownloadTask *)task {

    task.taskState = TaskStateDownloading;
    Downloader *downloader = [self downloaderWithTask:task];
    downloader.obj = task;
    NBLog(@"tasks count before resuming: %d", [[_downloadQueue operations] count]);
    [_downloadQueue addOperation:downloader];
    NBLog(@"tasks count after resuming: %d", [[_downloadQueue operations] count]);
    
    [self postNotification:TDownloaderWillStartTaskNotification object:task userInfo:nil];
}

- (void)pauseDownloadTask:(DownloadTask *)task {
    // 逻辑:
    // 1. 首先应取消下载，然后还原至ready状态，这样在恢复的时候才可以重新添加到队列
    // 2. 接着设置taskstate为pause，这样可以让前端知道当前的状态
    // 解决思路: 由于Downloader不提供改变ready状态的外部接口，所以考虑以下两种解决方案
    // 方案1. 考虑重新初始化一个新的downloader进行深拷贝
    // 方案2. 为Downloader添加reset供外部调用的接口，待测试是否会影响其他逻辑判断 (测试证明该方法不可行，必须重新初始化一个新的operation)
    
    Downloader *download = [self isExist:task];
    if (download) {
        task.taskState = TaskStatePausing;
        download.obj = task;
        [download cancel];
        [self postNotification:TDownloaderWillPauseTaskNotification object:task userInfo:nil];
    }
    else {
        NBLog(@"%@ is not in queue", task);
    }
}

- (void)cancelDownloadTask:(DownloadTask *)task {

    Downloader *download = [self isExist:task];
    if (download) {
        task.taskState = TaskStateCancelling;
        download.obj = task;
        [download cancel];
        [self postNotification:TDownloaderWillCancelTaskNotification object:task userInfo:nil];
    }
    else {
        NBLog(@"%@ is not in queue", task);
    }
}

@end

@implementation NSString (Extra)

- (NSString *)md5 {
    const char *cStr = [self UTF8String];
    unsigned char result[16];
    CC_MD5(cStr, strlen(cStr), result);
    return [NSString stringWithFormat:
			@"%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X",
			result[0], result[1], result[2], result[3],
			result[4], result[5], result[6], result[7],
			result[8], result[9], result[10], result[11],
			result[12], result[13], result[14], result[15]
			];
}

+ (NSString *)pathForTemporaryFileWithPrefix:(NSString *)prefix{
	//    NSString    *result;
    CFUUIDRef    uuid;
    CFStringRef  uuidStr;
    uuid = CFUUIDCreate(NULL);
    
    uuidStr = CFUUIDCreateString(NULL, uuid);
    
	//    result  = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@", prefix, uuidStr]];
	//    NBLog(@"\npathForTemporaryFileWithPrefix:\n%@",result);
    CFRelease(uuidStr);
    CFRelease(uuid);
    
	NSString *defaultPath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask,YES) lastObject] stringByAppendingPathComponent:prefix];
	
    return defaultPath;
}

@end
