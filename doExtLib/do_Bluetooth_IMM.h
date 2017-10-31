//
//  do_Bluetooth_MM.h
//  DoExt_MM
//
//  Created by @userName on @time.
//  Copyright (c) 2015年 DoExt. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol do_Bluetooth_IMM <NSObject>
//实现同步或异步方法，parms中包含了所需用的属性
- (void)close:(NSArray *)parms;
- (void)connect:(NSArray *)parms;
- (void)disable:(NSArray *)parms;
- (void)enable:(NSArray *)parms;
- (void)open:(NSArray *)parms;
- (void)startScan:(NSArray *)parms;
- (void)stopScan:(NSArray *)parms;
- (void)write:(NSArray *)parms;
- (void)registerListener:(NSArray*)parms;
@end
