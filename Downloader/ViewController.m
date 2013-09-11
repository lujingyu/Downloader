//
//  ViewController.m
//  Downloader
//
//  Created by jingyu lu on 9/9/13.
//  Copyright (c) 2013 jingyu lu. All rights reserved.
//

#import "ViewController.h"
#import "TDownloadManager.h"
#import "Book.h"

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
    
	[center addObserver:self selector:@selector(downloadDidReceiveResponse:) name:TDownloaderReceiveResponseNotification object:nil];
	[center addObserver:self selector:@selector(downloadDidReceiveData:) name:TDownloaderReceiveDataNotification object:nil];
	[center addObserver:self selector:@selector(downloadDidFinish:) name:TDownloaderFinishNotification object:nil];
	[center addObserver:self selector:@selector(downloadDidFail:) name:TDownloaderFailNotification object:nil];
    
    [center addObserver:self selector:@selector(downloadWillStart:) name:TDownloaderWillStartTaskNotification object:nil];
	[center addObserver:self selector:@selector(downloadWillPause:) name:TDownloaderWillPauseTaskNotification object:nil];
	[center addObserver:self selector:@selector(downloadWillCancel:) name:TDownloaderWillCancelTaskNotification object:nil];
	[center addObserver:self selector:@selector(downloadDidCancel:) name:TDownloaderDidCancelTaskNotification object:nil];
}

- (void)removeNotificationObserver {
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    
    [center removeObserver:self name:TDownloaderReceiveResponseNotification object:nil];
    [center removeObserver:self name:TDownloaderReceiveDataNotification object:nil];
    [center removeObserver:self name:TDownloaderFinishNotification object:nil];
    [center removeObserver:self name:TDownloaderFailNotification object:nil];
    
    [center removeObserver:self name:TDownloaderWillStartTaskNotification object:nil];
    [center removeObserver:self name:TDownloaderWillPauseTaskNotification object:nil];
    [center removeObserver:self name:TDownloaderWillCancelTaskNotification object:nil];
    [center removeObserver:self name:TDownloaderDidCancelTaskNotification object:nil];
}

- (void)downloadWillStart:(NSNotification *)notification {
    [self viewOnBook:[notification object]];
}

- (void)downloadWillPause:(NSNotification *)notification {
    [self viewOnBook:[notification object]];
}

- (void)downloadWillCancel:(NSNotification *)notification {
    [self viewOnBook:[notification object]];
}

- (void)downloadDidCancel:(NSNotification *)notification {
    [self viewOnBook:[notification object]];
}

- (void)downloadDidReceiveResponse:(NSNotification *)notification {
    [self viewOnBook:[notification object]];
}

- (void)downloadDidReceiveData:(NSNotification *)notification {
    [self viewOnBook:[notification object]];
}

- (void)downloadDidFinish:(NSNotification *)notification {
    [self viewOnBook:[notification object]];
}

- (void)downloadDidFail:(NSNotification *)notification {
    [self viewOnBook:[notification object]];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
	
	[self addNotificationObserver];
	
	_fakeDatasource = [[NSMutableArray alloc] initWithCapacity:0];
	NSString *str = @"http://dl_dir.qq.com/music/clntupate/QQMusicForMacV1.2.0.dmg";
	for (int i = 0; i < 10; i++) {
		NSString *path = [self pathForTemporaryFileWithPrefix:[NSString stringWithFormat:@"path%d", i]];
		Book *book = [[Book alloc] initWithURL:[NSURL URLWithString:str] tempPath:path];
		[_fakeDatasource addObject:book];
		[book release];
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
    [self actionOnBookAtIndex:index];
}

#pragma mark - 点击触发时，根据当前状态执行不同的动作

- (void)actionOnBookAtIndex:(NSInteger)index {
    Book *book = [_fakeDatasource objectAtIndex:index];
    switch (book.taskState) {
        case TaskStateNormal: {
            // 添加到下载
            [[TDownloadManager sharedInstance] addDownloadTask:book];
        }
            break;
        case TaskStateDownloading: {
            // 暂停
            [[TDownloadManager sharedInstance] pauseDownloadTask:book];
        }
            break;
        case TaskStatePausing: {
            // 恢复下载
            // 删除以前的operation, 然后初始化一个新的
            Book *newBook = [book getReady];
            [_fakeDatasource replaceObjectAtIndex:index withObject:newBook];
            [[TDownloadManager sharedInstance] resumeDownloadTask:newBook];
        }
            break;
        case TaskStateWaiting: {
            // 暂停
            [[TDownloadManager sharedInstance] pauseDownloadTask:book];
        }
            break;
        case TaskStateCancelling: {
            // 上一次状态为取消
            [[TDownloadManager sharedInstance] addDownloadTask:book];
        }
            break;
        case TaskStateDownloaded: {
            // 跳转详情
            NBLog(@"go to detail");
        }
            break;
        case TaskStateError: {
            // 添加到下载
            [[TDownloadManager sharedInstance] addDownloadTask:book];
        }
            break;
        default:
            break;
    }
}

#pragma mark - 根据当前的状态显示视图内容

- (void)viewOnBook:(Book *)book {
    NSInteger index = [_fakeDatasource indexOfObject:book];
    UIButton *btn = (UIButton *)[self.view viewWithTag:index+1000];

    switch (book.taskState) {
        case TaskStateNormal: {
            // 普通状态
            [btn setTitle:@"Normal" forState:UIControlStateNormal];
        }
            break;
        case TaskStateDownloading: {
            // 正在下载 显示进度条
            CGFloat progress = (double)book.totalBytesRead/(double)book.totalBytes;
            NSString *title = [NSString stringWithFormat:@"%1.f%%", progress*100];
            [btn setTitle:title forState:UIControlStateNormal];
        }
            break;
        case TaskStatePausing: {
            // 暂停 显示暂停图标
            [btn setTitle:@"Pause" forState:UIControlStateNormal];
        }
            break;
        case TaskStateWaiting: {
            // 等待 显示waiting
            [btn setTitle:@"Waiting" forState:UIControlStateNormal];
        }
            break;
        case TaskStateCancelling: {
            // 取消下载 显示成普通状态，或者删除?
            [btn setTitle:@"Deleting" forState:UIControlStateNormal];
        }
            break;
        case TaskStateDownloaded: {
            // 下载完成 显示完成的图标
            [btn setTitle:@"Done" forState:UIControlStateNormal];
        }
            break;
        case TaskStateError: {
            // 出错 显示暂停图标代替?
            [btn setTitle:@"Error" forState:UIControlStateNormal];
        }
            break;
        default:
            break;
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
