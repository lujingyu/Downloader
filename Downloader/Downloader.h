//
//  Downloader.h
//  LUDownloader
//
//  Created by jingyu lu on 1/4/13.
//  Copyright (c) 2013 Jingyu Lu. All rights reserved.
//

#import <Foundation/Foundation.h>

#define key_download_connection          @"key_download_connection"
#define key_download_response            @"key_download_response"
#define key_download_total_bytes_read    @"key_download_total_bytes_read"
#define key_download_total_bytes         @"key_download_total_bytes"
#define key_download_error               @"key_download_error"

@protocol DownloaderNotifyDelegate <NSObject>
@optional
- (void)downloadDidReceiveResponse:(NSNotification *)notification;
- (void)downloadDidReceiveData:(NSNotification *)notification;
- (void)downloadDidFinish:(NSNotification *)notification;
- (void)downloadDidFail:(NSNotification *)notification;
@end

extern NSString * const NotificationDownloadDidReceiveResponse;
extern NSString * const NotificationDownloadDidReceiveData;
extern NSString * const NotificationDownloadDidFinish;
extern NSString * const NotificationDownloadDidFail;

extern NSString * const DownloadPauseNotification;  // 当需要执行pause操作时，应该post本通知，DownloadQueue将会寻找下一个需要下载的对象
extern NSString * const DownloadResumeNotification; // 当需要执行resume操作时，应该post本通知，DownloadQueue将变更操作状态

typedef void (^DownloaderDidReceiveResponseBlock)(NSURLConnection *connection, unsigned long long totalBytesRead, unsigned long long totalBytes) ;
typedef void (^DownloaderDidReceiveDataBlock)(NSURLConnection *connection, unsigned long long totalBytesRead, unsigned long long totalBytes);
typedef void (^DownloaderDidFinishLoadingBlock)(NSURLConnection *connection);
typedef void (^DownloaderDidFailWithErrorBlock)(NSURLConnection *connection, NSError *error);

@interface Downloader : NSOperation <NSURLConnectionDelegate> 

@property (nonatomic, retain) NSObject  *obj; // 用于传递一些本地参数，Downloader类的内部不做调用

+ (id)downloaderWithURL:(NSURL *)url tempPath:(NSString *)tempPath;
/**
 @param url 下载链接地址
 @param tempPath 本地文件缓冲路径(一直到文件名)
 */
- (id)initWithURL:(NSURL *)url tempPath:(NSString *)tempPath;

- (void)start;
- (void)pause;
- (BOOL)isPaused;
- (BOOL)isReady; // isWaiting
- (void)resume;
- (void)cancel;
// added by ljy 5/9/2013
- (void)waiting;

#if NS_BLOCKS_AVAILABLE
@property (nonatomic, copy) DownloaderDidReceiveResponseBlock receiveResponseBlock;
@property (nonatomic, copy) DownloaderDidReceiveDataBlock receiveDataBlock;
@property (nonatomic, copy) DownloaderDidFinishLoadingBlock finishLoadingBlock;
@property (nonatomic, copy) DownloaderDidFailWithErrorBlock failWithErrorBlock;
#endif

@end
