//
//  ViewController.m
//  Downloader
//
//  Created by jingyu lu on 9/9/13.
//  Copyright (c) 2013 jingyu lu. All rights reserved.
//

#import "ViewController.h"
#import "TDownloadManager.h"

@interface ViewController ()

@end

@implementation ViewController

- (NSString *)pathForTemporaryFileWithPrefix:(NSString *)prefix{
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

- (void)addNotificationObserver {
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserver:self selector:@selector(downloadDidReceiveResponse:) name:NotificationDownloadDidReceiveResponse object:nil];
	[center addObserver:self selector:@selector(downloadDidReceiveData:) name:NotificationDownloadDidReceiveData object:nil];
	[center addObserver:self selector:@selector(downloadDidFinish:) name:NotificationDownloadDidFinish object:nil];
	[center addObserver:self selector:@selector(downloadDidFail:) name:NotificationDownloadDidFail object:nil];
}

- (void)downloadDidReceiveResponse:(NSNotification *)notification {
	Downloader *dl = [notification object];
	int index = [_fakeDatasource indexOfObject:dl];
	UIButton *btn = (UIButton *)[self.view viewWithTag:index+1000];
	[btn setTitle:@"Waiting" forState:UIControlStateNormal];
}

- (void)downloadDidReceiveData:(NSNotification *)notification {
	Downloader *dl = [notification object];
	int index = [_fakeDatasource indexOfObject:dl];
	UIButton *btn = (UIButton *)[self.view viewWithTag:index+1000];
	
	NSDictionary *userInfo = [notification userInfo];
	unsigned long long totalBytesRead = [[userInfo objectForKey:key_download_total_bytes_read] unsignedLongLongValue];
	unsigned long long totalBytes = [[userInfo objectForKey:key_download_total_bytes] unsignedLongLongValue];
	
	CGFloat progress = (double)totalBytesRead/(double)totalBytes;
	NSString *title = [NSString stringWithFormat:@"%1.f%%", progress*100];	
	[btn setTitle:title forState:UIControlStateNormal];
}

- (void)downloadDidFinish:(NSNotification *)notification {
	Downloader *dl = [notification object];
	int index = [_fakeDatasource indexOfObject:dl];
	UIButton *btn = (UIButton *)[self.view viewWithTag:index+1000];
	[btn setTitle:@"Done" forState:UIControlStateNormal];
}

- (void)downloadDidFail:(NSNotification *)notification {
	Downloader *dl = [notification object];
	int index = [_fakeDatasource indexOfObject:dl];
	UIButton *btn = (UIButton *)[self.view viewWithTag:index+1000];
	[btn setTitle:@"Failed" forState:UIControlStateNormal];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
	
	[self addNotificationObserver];
	
	_fakeDatasource = [[NSMutableArray alloc] initWithCapacity:0];
	NSString *str = @"http://www.baidupcs.com/file/e805857e0882c2be6706b29da2f19823?xcode=2c88a05b4c272c0bee366fb73b755c799bd3780af21cada6&fid=134615754-250528-4191677825&time=1378706578&sign=FDTAXER-DCb740ccc5511e5e8fedcff06b081203-s993xZzV0S3znBqgjaSXG%2BjplWQ%3D&to=wb&fm=N,B,M&expires=8h&rt=pr&r=304146050&logid=856051358";
	for (int i = 0; i < 10; i++) {
		NSString *path = [self pathForTemporaryFileWithPrefix:[NSString stringWithFormat:@"path%d", i]];
		Downloader *dl = [[Downloader alloc] initWithURL:[NSURL URLWithString:str] tempPath:path];
		[_fakeDatasource addObject:dl];
		[dl release];
	}
	[self drawUI];
}

- (void)drawUI {
	for (int i = 1000; i < [_fakeDatasource count]+1000; i++) {
		CGRect frame = CGRectMake(10, (i-1000)*46, 100, 46);
		UIButton *btn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
		btn.tag = i;
		[btn setTitle:[NSString stringWithFormat:@"%d", i] forState:UIControlStateNormal];
		[btn setFrame:frame];
		[btn addTarget:self action:@selector(actionButton:) forControlEvents:UIControlEventTouchUpInside];
		[self.view addSubview:btn];
	}
}

- (void)actionButton:(UIButton *)button {
	int index = button.tag-1000;
	Downloader *dl = [_fakeDatasource objectAtIndex:index];
	
//	typedef enum {
//		taskStateNormal,
//		taskStateDownloading,
//		taskStatePause,
//		taskStateResume,
//		taskStateDownloaded,
//		taskStateWaiting,
//		taskStateError,
//	} TaskState;

	if ([dl isExecuting] == YES) {
		// do pause
		// 只有将NSOperation的isFinished置为YES时，其所在的队列NSOperationQueue才会释放当前operation，并执行下一个operation
		[dl cancel];
		
	}
	else if ([dl isPaused] == YES) {
		// do resume
		[dl resume];
	}
	else {
		[[TDownloadManager sharedInstance] addDownloadTask:dl];
	}
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
