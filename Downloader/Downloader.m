//
//  Downloader.m
//  LUDownloader
//
//  Created by jingyu lu on 1/4/13.
//  Copyright (c) 2013 Jingyu Lu. All rights reserved.
//

#import  "Downloader.h"
#import  <CommonCrypto/CommonDigest.h>
#include <fcntl.h>

#define credential_user       @"lujingyu"
#define credential_password   @"12341234"

#define IncompleteDownload   @"DownloadCache"

NSString * const kDownloadLockName = @"com.downloading.operation.lock";

NSString * const DownloadDidStartNotification  = @"notification.downloading.operation.start";
NSString * const DownloadDidFinishNotification = @"notification.downloading.operation.finish";
NSString * const DownloadPauseNotification = @"notification.downloading.operation.pause";
NSString * const DownloadResumeNotification = @"notification.downloading.operation.resume";

NSString * const NotificationDownloadDidReceiveResponse = @"download.receive.response";
NSString * const NotificationDownloadDidReceiveData     = @"download.receive.data";
NSString * const NotificationDownloadDidFinish          = @"download.finish";
NSString * const NotificationDownloadDidFail            = @"download.fail";

typedef enum {
	DownloaderOperationStatePaused      = -1,
	DownloaderOperationStateReady       =  1,
	DownloaderOperationStateExecuting   =  2,
	DownloaderOperationStateFinished    =  3,
} DownloaderOperationState;

@interface Downloader () {
	
	DownloaderDidReceiveResponseBlock _receiveResponseBlock;
	DownloaderDidReceiveDataBlock     _receiveDataBlock;
	DownloaderDidFinishLoadingBlock   _finishLoadingBlock;
	DownloaderDidFailWithErrorBlock   _failWithErrorBlock;
}

@property (readwrite, nonatomic, assign) DownloaderOperationState state;
@property (readwrite, nonatomic, assign, getter = isCancelled) BOOL cancelled;
@property (readwrite, nonatomic, strong) NSRecursiveLock *lock;
@property (readwrite, nonatomic, strong) NSURLConnection *connection;
@property (readwrite, nonatomic, strong) NSMutableURLRequest *request;
@property (readwrite, nonatomic, strong) NSURLResponse *response;
@property (readwrite, nonatomic, strong) NSError *error;
@property (readwrite, nonatomic, strong) NSData *responseData;
@property (readwrite, nonatomic, copy)   NSString *responseString;
/**
 totalBytesRead 已经读到的字节长度
 */
@property (readwrite, nonatomic, assign) long long totalBytesRead;
/**
 totalBytes 总共的字节长度
 */
@property (readwrite, nonatomic, assign) long long totalBytes;
/**
 暂未用到
 */
@property (readwrite, nonatomic, strong) NSInputStream *inputStream;
/**
 用于缓冲文件
 */
@property (readwrite, nonatomic, strong) NSOutputStream *outputStream;
/**
 默认为NSRunLoopCommonModes
 */
@property (readwrite, nonatomic, strong) NSSet *runLoopModes;
/**
 缓冲文件的路径
 */
@property (readwrite, nonatomic, copy) NSString *targetPath;

@end

@implementation Downloader

@synthesize obj = _obj;

@synthesize state = _state;
@synthesize cancelled = _cancelled;
@synthesize lock = _lock;
@synthesize connection = _connection;
@synthesize request = _request;
@synthesize response = _response;
@synthesize error = _error;
@synthesize responseData = _responseData;
@synthesize responseString = _responseString;
@synthesize totalBytesRead = _totalBytesRead;
@synthesize totalBytes = _totalBytes;
@synthesize inputStream = _inputStream;
@synthesize outputStream = _outputStream;
@synthesize runLoopModes = _runLoopModes;
@synthesize targetPath = _targetPath;

@synthesize receiveResponseBlock = _receiveResponseBlock;
@synthesize receiveDataBlock = _receiveDataBlock;
@synthesize finishLoadingBlock = _finishLoadingBlock;
@synthesize failWithErrorBlock = _failWithErrorBlock;

#pragma mark - inline function

static inline NSString *keyPathFromOperationState(DownloaderOperationState state) {
    switch (state) {
        case DownloaderOperationStateReady:
            return @"isReady";
        case DownloaderOperationStateExecuting:
            return @"isExecuting";
        case DownloaderOperationStateFinished:
            return @"isFinished";
        case DownloaderOperationStatePaused:
            return @"isPaused";
        default:
            return @"state";
    }
}

static inline BOOL downloaderStateTransitionIsValid(DownloaderOperationState fromState, DownloaderOperationState toState, BOOL isCancelled) {
    if (fromState == DownloaderOperationStateFinished && toState == DownloaderOperationStateReady) {
        return YES;
    }
    switch (fromState) {
        case DownloaderOperationStateReady:
            switch (toState) {
                case DownloaderOperationStatePaused:
                case DownloaderOperationStateExecuting:
                    return YES;
                case DownloaderOperationStateFinished:
                    return isCancelled;
                default:
                    return NO;
            }
        case DownloaderOperationStateExecuting:
            switch (toState) {
                case DownloaderOperationStatePaused:
                case DownloaderOperationStateFinished:
                    return YES;
                default:
                    return NO;
            }
        case DownloaderOperationStateFinished:
            return NO;
        case DownloaderOperationStatePaused:
            return toState == DownloaderOperationStateReady;
        default:
            return YES;
    }
}

#pragma mark - private

// calculates the MD5 hash of a key
+ (NSString *)md5StringForString:(NSString *)string {
    const char *str = [string UTF8String];
    unsigned char r[CC_MD5_DIGEST_LENGTH];
    CC_MD5(str, strlen(str), r);
    return [NSString stringWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
            r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], r[10], r[11], r[12], r[13], r[14], r[15]];
}

+ (NSString *)cacheFolder {
    static NSString *cacheFolder;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *cacheDir = NSTemporaryDirectory();
        cacheFolder = [cacheDir stringByAppendingPathComponent:IncompleteDownload];
        
        // ensure all cache directories are there (needed only once)
        NSError *error = nil;
        if(![[NSFileManager new] createDirectoryAtPath:cacheFolder withIntermediateDirectories:YES attributes:nil error:&error]) {
            NBLog(@"Failed to create cache directory at %@", cacheFolder);
        }
    });
    return cacheFolder;
}

- (unsigned long long)fileSizeForPath:(NSString *)path {
    unsigned long long fileSize = 0;
    NSFileManager *fileManager = [NSFileManager new]; // not thread safe
    if ([fileManager fileExistsAtPath:path]) {
        NSError *error = nil;
        NSDictionary *fileDict = [fileManager attributesOfItemAtPath:path error:&error];
        if (!error && fileDict) {
            fileSize = [fileDict fileSize];
        }
    }
    return fileSize;
}

- (BOOL)deleteTempFileWithError:(NSError **)error {
    NSFileManager *fileManager = [NSFileManager new];
    BOOL success = YES;
    @synchronized(self) {
        NSString *tempPath = [self tempPath];
        if ([fileManager fileExistsAtPath:tempPath]) {
            success = [fileManager removeItemAtPath:[self tempPath] error:error];
        }
    }
    return success;
}

- (NSString *)tempPath {
    NSString *tempPath = nil;
    if (self.targetPath) {
        NSString *md5URLString = [[self class] md5StringForString:self.targetPath];
        tempPath = [[[self class] cacheFolder] stringByAppendingPathComponent:md5URLString];
    }
    return tempPath;
}

#pragma mark - static

+ (void) __attribute__((noreturn)) networkRequestThreadEntryPoint:(id)__unused object {
    do {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] run];
        }
    } while (YES);
}

+ (NSThread *)networkRequestThread {
    static NSThread *_networkRequestThread = nil;
    static dispatch_once_t oncePredicate;
	
    dispatch_once(&oncePredicate, ^{
        _networkRequestThread = [[NSThread alloc] initWithTarget:self selector:@selector(networkRequestThreadEntryPoint:) object:nil];
        [_networkRequestThread start];
    });
	
    return _networkRequestThread;
}

#pragma mark - life cycle

+ (id)downloaderWithURL:(NSURL *)url tempPath:(NSString *)tempPath {
	return [[[self alloc] initWithURL:url tempPath:tempPath] autorelease];
}

- (id)initWithURL:(NSURL *)url tempPath:(NSString *)tempPath {
	if (self = [super init]) {
		
		/**
		 流程:
		 1. 根据url与destinationPath索引到缓存文件
		 2. 根据resume，判断是否需要断点续传
		 如果YES，初始化对应的request
		 如果NO，初始化对应的request后，将缓存文件删除
		 */
		
		self.targetPath = tempPath;
		self.lock = [[[NSRecursiveLock alloc] init] autorelease];
		self.lock.name = kDownloadLockName;
		self.runLoopModes = [NSSet setWithObject:NSRunLoopCommonModes];
		self.state = DownloaderOperationStateReady;
		
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
		[request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
		self.request = request;
		
		self.outputStream = [NSOutputStream outputStreamToFileAtPath:self.targetPath append:YES];
	}
	return self;
}

- (void)dealloc {
	self.obj = nil;
	self.lock = nil;
	self.connection = nil;
	self.request = nil;
	self.response = nil;
	self.error = nil;
	self.responseData = nil;
	self.responseString = nil;
	self.runLoopModes = nil;
	self.targetPath = nil;
	if (self.inputStream) {
		[self.inputStream close];
		self.inputStream = nil;
	}
	if (self.outputStream) {
		[self.outputStream close];
		self.outputStream = nil;
	}
	
#if NS_BLOCKS_AVAILABLE
	[self releaseBlocksOnMainThread];
#endif
	
	[super dealloc];
}

#if NS_BLOCKS_AVAILABLE
- (void)releaseBlocksOnMainThread {
	NSMutableArray *blocks = [NSMutableArray arrayWithCapacity:0];
	if (_receiveResponseBlock) {
		[blocks addObject:_receiveResponseBlock];
		[_receiveResponseBlock release];
		_receiveResponseBlock = nil;
	}
	if (_receiveDataBlock) {
		[blocks addObject:_receiveDataBlock];
		[_receiveDataBlock release];
		_receiveDataBlock = nil;
	}
	if (_finishLoadingBlock) {
		[blocks addObject:_finishLoadingBlock];
		[_finishLoadingBlock release];
		_finishLoadingBlock = nil;
	}
	if (_failWithErrorBlock) {
		[blocks addObject:_failWithErrorBlock];
		[_failWithErrorBlock release];
		_failWithErrorBlock = nil;
	}
	[[self class] performSelectorOnMainThread:@selector(releaseBlocks:) withObject:blocks waitUntilDone:[NSThread isMainThread]];
}

// Always called on main thread
+ (void)releaseBlocks:(NSArray *)blocks {
	
	// Blocks will be released when this method exits
}
#endif

#pragma mark - state

- (void)setState:(DownloaderOperationState)state {
    [self.lock lock];
    if (downloaderStateTransitionIsValid(self.state, state, [self isCancelled])) {
        NSString *oldStateKey = keyPathFromOperationState(self.state);
        NSString *newStateKey = keyPathFromOperationState(state);
        
        [self willChangeValueForKey:newStateKey];
        [self willChangeValueForKey:oldStateKey];
        _state = state;
        [self didChangeValueForKey:oldStateKey];
        [self didChangeValueForKey:newStateKey];
        
        switch (state) {
            case DownloaderOperationStateExecuting:
                [[NSNotificationCenter defaultCenter] postNotificationName:DownloadDidStartNotification object:self];
                break;
            case DownloaderOperationStateFinished:
                [[NSNotificationCenter defaultCenter] postNotificationName:DownloadDidFinishNotification object:self];
                break;
            default:
                break;
        }
    }
    [self.lock unlock];
}

- (BOOL)isReady {
    return self.state == DownloaderOperationStateReady && [super isReady];
}

- (BOOL)isExecuting {
    return self.state == DownloaderOperationStateExecuting;
}

- (BOOL)isFinished {
    return self.state == DownloaderOperationStateFinished;
}

- (BOOL)isConcurrent {
    return YES;
}

- (BOOL)isPaused {
    return self.state == DownloaderOperationStatePaused;
}

#pragma mark - action

- (void)operationDidStart {
    [self.lock lock];
    if ([self isCancelled]) {
        [self finish];
    } else {
		
		unsigned long long downloadedBytes = [self fileSizeForPath:self.targetPath];
		if (downloadedBytes > 0) {
			NSString *requestRange = [NSString stringWithFormat:@"bytes=%llu-", downloadedBytes];
			[self.request setValue:requestRange forHTTPHeaderField:@"Range"];
		}
		
        self.connection = [[[NSURLConnection alloc] initWithRequest:self.request delegate:self startImmediately:NO] autorelease];
		
        NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
        for (NSString *runLoopMode in self.runLoopModes) {
            [self.connection scheduleInRunLoop:runLoop forMode:runLoopMode];
            [self.outputStream scheduleInRunLoop:runLoop forMode:runLoopMode];
        }
        
        [self.connection start];
    }
    [self.lock unlock];
}

- (void)start {
	
    [self.lock lock];
    if ([self isReady]) {
        self.state = DownloaderOperationStateExecuting;
        [self performSelector:@selector(operationDidStart) onThread:[[self class] networkRequestThread] withObject:nil waitUntilDone:NO modes:[self.runLoopModes allObjects]];
    }
    [self.lock unlock];
}

- (void)pause {
	
	if ([self isPaused] || [self isFinished] || [self isCancelled]) {
        return;
    }
	
    [self.lock lock];
	
    if ([self isExecuting]) {
        [self.connection performSelector:@selector(cancel) onThread:[[self class] networkRequestThread] withObject:nil waitUntilDone:NO modes:[self.runLoopModes allObjects]];
		
        dispatch_async(dispatch_get_main_queue(), ^{
			[[NSNotificationCenter defaultCenter] postNotificationName:DownloadDidFinishNotification object:self];
        });
    }
	
    self.state = DownloaderOperationStatePaused;
	
    [self.lock unlock];
}

- (void)resume {
    if (![self isPaused]) {
        return;
    }
    
    [self.lock lock];
    self.state = DownloaderOperationStateReady;
    
    [self start];
    [self.lock unlock];
}

- (void)finish {
    self.state = DownloaderOperationStateFinished;
}

- (void)getReady {
    self.state = DownloaderOperationStateReady;
}

- (void)cancel {
    [self.lock lock];
    if (![self isFinished] && ![self isCancelled]) {
        [self willChangeValueForKey:@"isCancelled"];
        _cancelled = YES;
        [super cancel];
        [self didChangeValueForKey:@"isCancelled"];
		
        // Cancel the connection on the thread it runs on to prevent race conditions
        [self performSelector:@selector(cancelConnection) onThread:[[self class] networkRequestThread] withObject:nil waitUntilDone:NO modes:[self.runLoopModes allObjects]];
    }
    [self.lock unlock];
}

- (void)cancelConnection {
    if (self.connection) {
        [self.connection cancel];
        
        // Manually send this delegate message since `[self.connection cancel]` causes the connection to never send another message to its delegate
        NSDictionary *userInfo = nil;
        if ([self.request URL]) {
            userInfo = [NSDictionary dictionaryWithObject:[self.request URL] forKey:NSURLErrorFailingURLErrorKey];
        }
        [self performSelector:@selector(connection:didFailWithError:) withObject:self.connection withObject:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:userInfo]];
    }
}

#pragma mark -

- (NSString *)responseString {
    [self.lock lock];
    if (!_responseString && self.response && self.responseData) {
        NSStringEncoding textEncoding = NSUTF8StringEncoding;
        if (self.response.textEncodingName) {
            textEncoding = CFStringConvertEncodingToNSStringEncoding(CFStringConvertIANACharSetNameToEncoding((CFStringRef)self.response.textEncodingName));
        }
        self.responseString = [[[NSString alloc] initWithData:self.responseData encoding:textEncoding] autorelease];
    }
    [self.lock unlock];
    
    return _responseString;
}

#pragma mark - connection delegate

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse {
    return nil;
}

- (NSURLRequest *)connection: (NSURLConnection *)inConnection
             willSendRequest: (NSURLRequest *)inRequest
            redirectResponse: (NSURLResponse *)inRedirectResponse {
    NSMutableString *headers = [[[NSMutableString alloc] init] autorelease];
    if (inRequest) {
        NSDictionary *sentHeaders = [inRequest allHTTPHeaderFields];
        for (NSString *key in sentHeaders) {
            [headers appendFormat:@"%@: %@\n", key, [sentHeaders objectForKey:key]];
        }
		NBLog(@"%@", headers);
    }
    
    if (inRedirectResponse) {
		NSMutableURLRequest *r = [[inRequest mutableCopy] autorelease]; // original request
		[r setURL: [inRequest URL]];
		[r setHTTPMethod:[_request HTTPMethod]]; // Method isn't copied to inRequest automatically
		return r;
    }
	else {
        return inRequest;
    }
}

- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace {
    if ([protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodClientCertificate]) {
        return NO;
    } else if ([protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        return YES;
    } else {
        return YES;
    }
}

-(void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
	
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        [challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge];
        [challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
    } else {
        if ([challenge previousFailureCount] == 0) {
            NSURLCredential *newCredential;
            newCredential = [NSURLCredential credentialWithUser:credential_user
                                                       password:credential_password
                                                    persistence:NSURLCredentialPersistenceNone];
            [[challenge sender] useCredential:newCredential forAuthenticationChallenge:challenge];
        } else {
            [[challenge sender] cancelAuthenticationChallenge:challenge];
			NBLog(@"Authentication Failed");
        }
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
	self.response = response;
	
	NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
	NBLog(@"%d", httpResponse.statusCode);
	NBLog(@"%@", httpResponse.allHeaderFields);
	
	if (httpResponse.statusCode >= 200 && httpResponse.statusCode <= 299) {
		[self.outputStream open];
		self.totalBytesRead = 0;
		self.totalBytes = [[httpResponse.allHeaderFields valueForKey:@"Content-Length"] floatValue];
		
		if(httpResponse.statusCode == 206) {
			// 206: 客户端发送了一个带有Range头的GET请求
			NSString *contentRange = [httpResponse.allHeaderFields valueForKey:@"Content-Range"];
			if ([contentRange hasPrefix:@"bytes"]) {
				NSArray *bytes = [contentRange componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" -/"]];
				if ([bytes count] == 4) {
					self.totalBytesRead = [[bytes objectAtIndex:1] longLongValue];
					self.totalBytes = [[bytes objectAtIndex:2] longLongValue]; // if this is *, it's converted to 0
				}
			}
		}
	}
	
	if (_receiveResponseBlock) {
		_receiveResponseBlock(connection, self.totalBytesRead, self.totalBytes);
	}
	
	NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
							  connection,  key_download_connection,
							  response,    key_download_response,
							  nil];
	[[NSNotificationCenter defaultCenter] postNotificationName:NotificationDownloadDidReceiveResponse
														object:self
													  userInfo:userInfo];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
	
	NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)self.response;
	
	if(httpResponse.statusCode >= 200 && httpResponse.statusCode <= 299) {
		self.totalBytesRead += [data length];
		
		if ([self.outputStream hasSpaceAvailable]) {
			const uint8_t *dataBuffer = (uint8_t *) [data bytes];
			[self.outputStream write:&dataBuffer[0] maxLength:[data length]];
		}
	}
	
	if (_receiveDataBlock) {
		_receiveDataBlock(connection, self.totalBytesRead, self.totalBytes);
	}
	
	NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
							  connection,                                                key_download_connection,
							  [NSNumber numberWithUnsignedLongLong:self.totalBytesRead], key_download_total_bytes_read,
							  [NSNumber numberWithUnsignedLongLong:self.totalBytes],     key_download_total_bytes,
							  nil];
	[[NSNotificationCenter defaultCenter] postNotificationName:NotificationDownloadDidReceiveData
														object:self
													  userInfo:userInfo];
	
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
	
	NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)self.response;
	
	if(httpResponse.statusCode >= 200 && httpResponse.statusCode <= 299) {
		self.responseData = [self.outputStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
		[self.outputStream close];
		[self finish];
		if (_finishLoadingBlock) {
			_finishLoadingBlock(connection);
		}
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
								  connection,   key_download_connection,
								  nil];
		[[NSNotificationCenter defaultCenter] postNotificationName:NotificationDownloadDidFinish
															object:self
														  userInfo:userInfo];
	}
	else {
		[self.outputStream close];
		[self pause];
		self.error = [NSError errorWithDomain:@"httpResponse.statusCode" code:httpResponse.statusCode userInfo:nil];
		if (_failWithErrorBlock) {
			_failWithErrorBlock(connection, self.error);
		}
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
								  connection,   key_download_connection,
								  self.error,   key_download_error,
								  nil];
		[[NSNotificationCenter defaultCenter] postNotificationName:NotificationDownloadDidFail
															object:self
														  userInfo:userInfo];
	}
	
	self.connection = nil;
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
	
	self.error = error;
    
    [self.outputStream close];
    
    [self finish];
	
	
	if (_failWithErrorBlock) {
		_failWithErrorBlock(connection, error);
	}
	
	NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
							  connection,   key_download_connection,
							  self.error,   key_download_error,
							  nil];
	[[NSNotificationCenter defaultCenter] postNotificationName:NotificationDownloadDidFail
														object:self
													  userInfo:userInfo];
    self.connection = nil;
}

#pragma mark - block

#if NS_BLOCKS_AVAILABLE
- (void)setReceiveResponseBlock:(DownloaderDidReceiveResponseBlock)block {
	[_receiveResponseBlock release];
	_receiveResponseBlock = [block copy];
}

- (void)setReceiveDataBlock:(DownloaderDidReceiveDataBlock)block {
	[_receiveDataBlock release];
	_receiveDataBlock = [block copy];
}

- (void)setFinishLoadingBlock:(DownloaderDidFinishLoadingBlock)block {
	[_finishLoadingBlock release];
	_finishLoadingBlock = [block copy];
}

- (void)setFailWithErrorBlock:(DownloaderDidFailWithErrorBlock)block {
	[_failWithErrorBlock release];
	_failWithErrorBlock = [block copy];
}
#endif

@end
