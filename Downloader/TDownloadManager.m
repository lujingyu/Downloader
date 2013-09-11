//
//  TDownloadManager.m
//  Downloader
//
//  Created by jingyu lu on 9/9/13.
//  Copyright (c) 2013 jingyu lu. All rights reserved.
//

#import "TDownloadManager.h"

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
		_downloadQueue = [[NSOperationQueue alloc] init];
		_downloadQueue.maxConcurrentOperationCount = 1;
	}
	return self;
}

- (void)addDownloadTask:(Downloader *)download {
	NBLog(@"tasks count before adding: %d", [[_downloadQueue operations] count]);
	[_downloadQueue addOperation:download];
	NBLog(@"tasks count after adding: %d", [[_downloadQueue operations] count]);
}

@end
