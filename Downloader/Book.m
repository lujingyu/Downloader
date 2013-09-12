//
//  Book.m
//  Downloader
//
//  Created by lujingyu on 13-9-11.
//  Copyright (c) 2013年 jingyu lu. All rights reserved.
//

#import "Book.h"

@implementation Book

- (void)dealloc {
    self.bookID = nil;
    self.bookName = nil;
    [super dealloc];
}

//- (Book *)getReady {
//    Book *book = (Book *)[super getReady];
//    book.bookID = self.bookID;
//    book.bookName = self.bookName;
//    return book;
//}

@end
