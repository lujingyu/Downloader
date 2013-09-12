//
//  DownloadTask.h
//  Downloader
//
//  Created by lujingyu on 13-9-12.
//  Copyright (c) 2013年 jingyu lu. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum {
	TaskStateNormal = 0,
	TaskStateDownloading,
	TaskStatePausing,
    TaskStateWaiting,
    TaskStateCancelling,
	TaskStateDownloaded,
    TaskStateError,
} TaskState;

@interface DownloadTask : NSObject

@property (nonatomic, assign) unsigned long long totalBytesRead;
@property (nonatomic, assign) unsigned long long totalBytes;
@property (nonatomic, assign) TaskState taskState;
@property (nonatomic, retain) NSString *downloadURL;

- (void)readyToResume;
- (void)reset;

@end
