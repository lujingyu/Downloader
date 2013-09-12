//
//  Book.h
//  Downloader
//
//  Created by lujingyu on 13-9-11.
//  Copyright (c) 2013年 jingyu lu. All rights reserved.
//

#import "DownloadTask.h"


@interface Book : DownloadTask
@property (nonatomic, retain) NSString *bookID;
@property (nonatomic, retain) NSString *bookName;
@end
