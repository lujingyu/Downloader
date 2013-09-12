//
//  DownloadTask.m
//  Downloader
//
//  Created by lujingyu on 13-9-12.
//  Copyright (c) 2013年 jingyu lu. All rights reserved.
//

#import "DownloadTask.h"

@implementation DownloadTask

- (void)dealloc {
    self.downloadURL = nil;
    [super dealloc];
}

- (void)readyToResume {
    self.taskState = TaskStatePausing;
}

- (void)reset {
    self.taskState = TaskStateNormal;
    self.totalBytesRead = 0;
}

@end
