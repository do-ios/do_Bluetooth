//
//  do_Bluetooth_MM.m
//  DoExt_MM
//
//  Created by @userName on @time.
//  Copyright (c) 2015年 DoExt. All rights reserved.
//

#import "do_Bluetooth_MM.h"

#import "doScriptEngineHelper.h"
#import "doIScriptEngine.h"
#import "doInvokeResult.h"
#import "doJsonHelper.h"
#import <CoreBluetooth/CoreBluetooth.h>
#import "doDefines.h"
#import <UIKit/UIKit.h>
#import "doServiceContainer.h"
#import "doILogEngine.h"

@interface do_Bluetooth_MM()<CBCentralManagerDelegate,CBPeripheralDelegate>

/**
 中心管理者
 */
@property (nonatomic, strong) CBCentralManager *centralManager;

/**
 外围设备
 */
@property (nonatomic, strong) CBPeripheral *peripheral;

/**
 外围设备保存
 */
@property (nonatomic, strong) NSMutableArray *peripherals;

/**
 写特征数组
 */
@property (nonatomic, strong) NSMutableArray *writeChars;
/**
 读特征数组
 */
@property (nonatomic, strong) NSMutableArray *readChars;

@property (nonatomic, strong) NSString *callBackName;
@property (nonatomic, strong) id<doIScriptEngine> scriptEngine;

/**
 保存调用过read方法，且cUUID合法的可读特征UUID字符串数组
 */
@property (nonatomic, strong) NSMutableArray<NSString*> *haveReadCharacteristicUUIDArray;

@end

@implementation do_Bluetooth_MM

#pragma mark - 注册属性（--属性定义--）
/*
 [self RegistProperty:[[doProperty alloc]init:@"属性名" :属性类型 :@"默认值" : BOOL:是否支持代码修改属性]];
 */
-(void)OnInit
{
    [super OnInit];
    //注册属性
    self.peripherals = [NSMutableArray array];
    self.writeChars = [NSMutableArray array];
    self.readChars = [NSMutableArray array];
    self.haveReadCharacteristicUUIDArray = [NSMutableArray array];

}

//销毁所有的全局对象
-(void)Dispose
{
    //(self)类销毁时会调用递归调用该方法，在该类中主动生成的非原生的扩展对象需要主动调该方法使其销毁
    [_centralManager stopScan];
    _centralManager.delegate = nil;
    [self.peripherals removeAllObjects];
    [self.writeChars removeAllObjects];
    [self.haveReadCharacteristicUUIDArray removeAllObjects];
}

#pragma mark - priavte
- (NSData *)convertHexStrToData:(NSString *)str {
    if (!str || [str length] == 0) {
        return nil;
    }
    
    NSMutableData *hexData = [[NSMutableData alloc] initWithCapacity:8];
    NSRange range;
    if ([str length] % 2 == 0) {
        range = NSMakeRange(0, 2);
    } else {
        range = NSMakeRange(0, 1);
    }
    for (NSInteger i = range.location; i < [str length]; i += 2) {
        unsigned int anInt;
        NSString *hexCharStr = [str substringWithRange:range];
        NSScanner *scanner = [[NSScanner alloc] initWithString:hexCharStr];
        
        [scanner scanHexInt:&anInt];
        NSData *entity = [[NSData alloc] initWithBytes:&anInt length:1];
        [hexData appendData:entity];
        
        range.location += range.length;
        range.length = 2;
    }
    
    return hexData;
}

- (void)asyncMethodCalllBackWithResult:(doInvokeResult*)result tipErrorString:(NSString*)tipErrorString {
    [_scriptEngine Callback:_callBackName :result];
    if (tipErrorString) {
        [[doServiceContainer Instance].LogEngine WriteError:nil :tipErrorString];
    }
}
#pragma mark -
#pragma mark - 同步异步方法的实现
//同步
- (void)close:(NSArray *)parms
{
    //取消蓝牙链接
    if (self.centralManager != nil) {
        if (self.peripheral != nil) {
            [_centralManager cancelPeripheralConnection:self.peripheral];
            [self.haveReadCharacteristicUUIDArray removeAllObjects];
        }else {
            [[doServiceContainer Instance].LogEngine WriteError:nil :@"当前没有链接到外围蓝牙设备，无法关闭链接"];
        }
    }
}
- (void)disable:(NSArray *)parms
{
    //ios不支持
}
- (void)enable:(NSArray *)parms
{
    //ios不支持
}

- (void)stopScan:(NSArray *)parms
{
    //停止扫描
    [_centralManager stopScan];
}

// 异步
- (void)open:(NSArray *)parms
{
    //自己的代码实现
    _scriptEngine = [parms objectAtIndex:1];
    _callBackName = [parms objectAtIndex:2];
    //初始化manager
    dispatch_queue_t centralQueue = dispatch_queue_create("com.do.central", DISPATCH_QUEUE_CONCURRENT);
    _centralManager  = [[CBCentralManager alloc]initWithDelegate:self queue:centralQueue];
}

- (void)startScan:(NSArray *)parms
{
    _scriptEngine = [parms objectAtIndex:1];
    _callBackName = [parms objectAtIndex:2];
    doInvokeResult *result = [[doInvokeResult alloc] init];
    [result SetResultBoolean:true];
    if (_centralManager == nil) {
        [result SetResultBoolean:false];
        [self asyncMethodCalllBackWithResult:result tipErrorString:@"蓝牙组件未初始化，请先调用open初始化"];
        return;

    }
    [self asyncMethodCalllBackWithResult:result tipErrorString:nil];
    [_centralManager scanForPeripheralsWithServices:nil options:@{CBCentralManagerScanOptionAllowDuplicatesKey:@YES}];
}

- (void)connect:(NSArray *)parms
{
    NSDictionary *_dictParas = [parms objectAtIndex:0];
    _scriptEngine = [parms objectAtIndex:1];
    _callBackName = [parms objectAtIndex:2];
    NSString *address = [doJsonHelper GetOneText:_dictParas :@"address" :nil];
    if (!address) {
        doInvokeResult *connectResult = [[doInvokeResult alloc] init];
        [connectResult SetResultBoolean:false];
        [self asyncMethodCalllBackWithResult:connectResult tipErrorString:@"address 必传"]; //connect链接异步返回值
        return;
    }else {
        if ([address isEqualToString:@""]){
            doInvokeResult *connectResult = [[doInvokeResult alloc] init];
            [connectResult SetResultBoolean:false];
            [self asyncMethodCalllBackWithResult:connectResult tipErrorString:@"address 不能为空字符串"]; //connect链接异步返回值
            return;
        }
    }
    CBPeripheral *peripheral;
    for (CBPeripheral *tmpPer in self.peripherals) {
        if ([tmpPer.identifier.UUIDString isEqualToString:address]) {
            peripheral = tmpPer;
            break;
        }
    }
    if (peripheral) {
        //链接蓝牙
        [self.centralManager connectPeripheral:peripheral options:nil];
    }
}

- (void)write:(NSArray *)parms
{
    NSDictionary *_dictParas = [parms objectAtIndex:0];
    _scriptEngine = [parms objectAtIndex:1];
    _callBackName = [parms objectAtIndex:2];
    doInvokeResult *result = [[doInvokeResult alloc] init];
    
    // 优先
    if (_centralManager == nil) {
        [self asyncMethodCalllBackWithResult:result tipErrorString:@"蓝牙组件未初始化，无法执行写入操作"];
        return;
    }else {
        if (self.peripheral == nil) {
            [self asyncMethodCalllBackWithResult:result tipErrorString:@"当前未连接蓝牙外围设备，无法执行写入操作"];
            return;
        }
    }
    
    NSString *data = [doJsonHelper GetOneText:_dictParas :@"data" :@""];
    //    NSString *sUUID = [doJsonHelper GetOneText:_dictParas :@"sUUID" :@""];
    NSString *cUUID = [doJsonHelper GetOneText:_dictParas :@"cUUID" :nil];
    NSString *type = [doJsonHelper GetOneText:_dictParas :@"type": @"string"];
    type = type.lowercaseString;
    
    if (!cUUID) {
        [self asyncMethodCalllBackWithResult:result tipErrorString:@"cUUID 特征ID必传"];
        return;
    }else {
        if ([cUUID isEqualToString:@""]) {
            [self asyncMethodCalllBackWithResult:result tipErrorString:@"cUUID 特征ID不能为空字符串"];
            return;
        }
    }
    
    NSData *writeData;
    if ([type isEqualToString:@"string"]) {
        writeData = [data dataUsingEncoding:NSUTF8StringEncoding];
    }else if ([type isEqualToString:@"binary"]){
        writeData = [self convertHexStrToData:data];
    }else {
        [[doServiceContainer Instance].LogEngine WriteError:nil :@"type参数错误,只能为string或者binary,参数不填默认为string"];
        return;
    }
    
    
    CBCharacteristic *temCharacter;
    
    for (CBCharacteristic *character in self.writeChars) {
        if ([character.UUID.UUIDString isEqualToString:cUUID]) {
            temCharacter = character;
            break;
        }
    }
    
    if (temCharacter) {
        [self.peripheral writeValue:writeData forCharacteristic:temCharacter type:CBCharacteristicWriteWithResponse];
    }else { // 没有发现对应的写特征
        [self asyncMethodCalllBackWithResult:result tipErrorString:@"ccUUID 特征ID对应的特征不是一个可写的特征或特征不存在"];

        return;
    }
    
    [self asyncMethodCalllBackWithResult:result tipErrorString:nil];

}

- (void)read:(NSArray *)parms
{
    NSDictionary *_dictParas = [parms objectAtIndex:0];
    _scriptEngine = [parms objectAtIndex:1];
    _callBackName = [parms objectAtIndex:2];
    doInvokeResult *result = [[doInvokeResult alloc] init];
    NSString *sUUID = [doJsonHelper GetOneText:_dictParas :@"sUUID" :@""];
    NSString *cUUID = [doJsonHelper GetOneText:_dictParas :@"cUUID" :nil];

    // 优先
    if (_centralManager == nil) {
        [result SetResultInteger:-1];
        [self asyncMethodCalllBackWithResult:result tipErrorString:@"蓝牙组件未初始化，无法执行读操作"];
        return;
    }else {
        if (self.peripheral == nil) {
            [result SetResultInteger:-1];
            [self asyncMethodCalllBackWithResult:result tipErrorString:@"当前未连接蓝牙外围设备，无法执行读操作"];
            return;
        }
    }
    BOOL findTargetService = false;
    for (CBService *service in self.peripheral.services) {
        if ([service.UUID.UUIDString isEqualToString:sUUID]) {
            findTargetService = true;
            break;
        }
    }
    if (!findTargetService) {
        [result SetResultInteger:2];
        [self asyncMethodCalllBackWithResult:result tipErrorString:@"sUUID 服务ID对应的服务没找到"];
        return;
    }
    
    if (!cUUID) {
        [result SetResultInteger:-1];
        [self asyncMethodCalllBackWithResult:result tipErrorString:@"cUUID 特征ID必传"];
        return;
    }else {
        if ([cUUID isEqualToString:@""]) {
            [result SetResultInteger:-1];
            [self asyncMethodCalllBackWithResult:result tipErrorString:@"cUUID 特征ID不能为空字符串"];
            return;
        }
    }
    
    CBCharacteristic *temCharacter;
    
    for (CBCharacteristic *character in self.readChars) {
        if ([character.UUID.UUIDString isEqualToString:cUUID]) {
            temCharacter = character;
            break;
        }
    }
    if (temCharacter) {
        // 存储合法的cUUID-> didUpdateValueForCharacteristic方法中处理read方法回调用
        if (![self.haveReadCharacteristicUUIDArray containsObject:cUUID]) {
            [self.haveReadCharacteristicUUIDArray addObject:cUUID];
        }
        [self.peripheral readValueForCharacteristic:temCharacter];
    }else {
        [result SetResultInteger:3];
        [self asyncMethodCalllBackWithResult:result tipErrorString:@"cUUID 特征ID对应的特征不存在"];
        return;
    }
    
}

- (void)registerListener:(NSArray *)parms {
    NSDictionary *_dictParas = [parms objectAtIndex:0];
    _scriptEngine = [parms objectAtIndex:1];
    _callBackName = [parms objectAtIndex:2];
    doInvokeResult *result = [[doInvokeResult alloc] init];
    
    NSString *sUUID = [doJsonHelper GetOneText:_dictParas :@"sUUID" :nil];
    NSString *cUUID = [doJsonHelper GetOneText:_dictParas :@"cUUID" :nil];
    
    // 优先
    if (_centralManager == nil) {
        [result SetResultInteger:-1];
        [self asyncMethodCalllBackWithResult:result tipErrorString:@"蓝牙组件未初始化，无法执行注册监听操作"];
        return;
    }else {
        if (self.peripheral == nil) {
            [result SetResultInteger:-1];
            [self asyncMethodCalllBackWithResult:result tipErrorString:@"当前未连接蓝牙外围设备，无法执行注册监听读操作"];
            return;
        }
    }

    if (sUUID) {
        if (![sUUID isEqualToString:@""]) { // sUUID不为空字符串
            CBService *targetService;
            for (CBService *service in self.peripheral.services) {
                if ([service.UUID.UUIDString isEqualToString:sUUID]) {
                    targetService = service;
                    break;
                }
            }
            
            if (targetService) { // serviceUUID找到
                if (cUUID) {
                    if (![cUUID isEqualToString:@""]) { // cUUID不为空字符串
                        CBCharacteristic *targetCharacteristic;
                        for (CBCharacteristic *characteristic in targetService.characteristics) {
                            if ([characteristic.UUID.UUIDString isEqualToString:cUUID]) {
                                targetCharacteristic = characteristic;
                                break;
                            }
                        }
                        
                        if (targetCharacteristic) { // cUUID对应的特征存在
                            if ((targetCharacteristic.properties & CBCharacteristicPropertyNotify) == CBCharacteristicPropertyNotify) {
                                // 开始注册监听
                                [self.peripheral setNotifyValue:YES forCharacteristic:targetCharacteristic];
                                
                            }else {
                                [result SetResultInteger:-1];
                                [self asyncMethodCalllBackWithResult:result tipErrorString:@"cUUID对应的特征不是一个notfy的特征,无法监听"];
                                return;
                            }
                        }else { // cUUID对应的特征不存在
                            [result SetResultInteger:3];
                            [self asyncMethodCalllBackWithResult:result tipErrorString:@"cUUID对应的特征不存在"];
                            return;
                        }
                        
                    }else {
                        [result SetResultInteger:-1];
                        [self asyncMethodCalllBackWithResult:result tipErrorString:@"特征UUID不能为空字符串"];
                        return;
                    }
                    
                }else {
                    [result SetResultInteger:-1];
                    [self asyncMethodCalllBackWithResult:result tipErrorString:@"特征UUID必传"];
                    return;
                }
                
            }else {
                [result SetResultInteger:2];
                [self asyncMethodCalllBackWithResult:result tipErrorString:@"sUUID对应的服务不存在"];
            }
            
        }else {
            [result SetResultInteger:-1];
            [self asyncMethodCalllBackWithResult:result tipErrorString:@"服务UUID不能为空字符串"];
            return;
        }
        
    }else {
        [result SetResultInteger:-1];
        [self asyncMethodCalllBackWithResult:result tipErrorString:@"服务UUID必传"];
        return;
    }
}


#pragma bluetooth代理方法
/**
 手机蓝牙状态
 @return return value description
 */
- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    int number = 3;
    switch (central.state) {
        case CBManagerStatePoweredOn:
            number = 0;
            break;
        case CBManagerStateUnsupported:
            number = 1;
            break;
        case CBManagerStatePoweredOff:
            number = 3;
            if (self.centralManager) {
                if (self.peripheral) {
                    [self.centralManager cancelPeripheralConnection:self.peripheral];
                    self.peripheral = nil;
                    [self.haveReadCharacteristicUUIDArray removeAllObjects];
                }
                self.centralManager = nil;
            }
            [[doServiceContainer Instance].LogEngine WriteInfo:@"设备蓝牙状态改变" :@"当前蓝牙未打开或已手动关闭蓝牙，请打开蓝牙后调用open方法初始化蓝牙组件"];
            
            break;
        default:
            break;
    }
    doInvokeResult *result = [[doInvokeResult alloc] init];
    [result SetResultInteger:number];
    [self asyncMethodCalllBackWithResult:result tipErrorString:nil];
}

//发现外围设备
- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary<NSString *,id> *)advertisementData RSSI:(NSNumber *)RSSI
{
    if (peripheral) {
        //添加保存外围设备，注意如果这里不保存外围设备（或者说peripheral没有一个强引用，无法到达连接成功（或失败）的代理方法，因为在此方法调用完就会被销毁
        if(![self.peripherals containsObject:peripheral]){
            [self.peripherals addObject:peripheral];
        }
        NSMutableDictionary *node = [NSMutableDictionary dictionary];
        [node setObject:peripheral.identifier.UUIDString forKey:@"address"];
        if (peripheral.name) {
            [node setObject:peripheral.name forKey:@"name"];
        }
        else
        {
            [node setObject:@"" forKey:@"name"];
        }
        [node setObject:RSSI forKey:@"RSSI"];
        doInvokeResult *invokeResult = [[doInvokeResult alloc]init];
        [invokeResult SetResultNode:node];
        [self.EventCenter FireEvent:@"scan" :invokeResult];
        
    }
}

//链接外围成功
- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
    //设置外围设备的代理为当前视图控制器
    peripheral.delegate = self;
    //外围设备开始寻找服务
    [peripheral discoverServices:nil];
    self.peripheral = peripheral;
    
    doInvokeResult *connectResult = [[doInvokeResult alloc] init];
    [connectResult SetResultBoolean:true];
    [self asyncMethodCalllBackWithResult:connectResult tipErrorString:nil]; //connect链接异步返回值

    
    //触发事件
    doInvokeResult *invokeResult = [[doInvokeResult alloc]init];
    [invokeResult SetResultInteger:1];
    [self.EventCenter FireEvent:@"connectionStateChange" :invokeResult];
}

//链接外围失败
- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    doInvokeResult *connectResult = [[doInvokeResult alloc] init];
    [connectResult SetResultBoolean:true];
    [self asyncMethodCalllBackWithResult:connectResult tipErrorString:nil]; //connect链接异步返回值
    
    doInvokeResult *invokeResult = [[doInvokeResult alloc]init];
    [invokeResult SetResultInteger:0];
    [self.EventCenter FireEvent:@"connectionStateChange" :invokeResult];

}

// 断开连接
- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(nullable NSError *)error {
    
    doInvokeResult *invokeResult = [[doInvokeResult alloc]init];
    [invokeResult SetResultInteger:0];
    [self.EventCenter FireEvent:@"connectionStateChange" :invokeResult];
}

//发现外围服务
-(void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error
{
    NSLog(@"已发现可用服务...");
    for (CBService *service in peripheral.services) {
        //遍历查找到的服务
        [peripheral discoverCharacteristics:nil forService:service];
    }
}
//发现服务的特征
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error
{
    if(error){
        NSLog(@"Discovered characteristics for %@ with error: %@", service.UUID, [error localizedDescription]);

    }
    for (CBCharacteristic *characteristic in service.characteristics) {
        if ((characteristic.properties & CBCharacteristicPropertyWrite)== CBCharacteristicPropertyWrite) {
            
            if(![self.writeChars containsObject:characteristic])
            {
                [self.writeChars addObject:characteristic];
            }
        }

        if ((characteristic.properties & CBCharacteristicPropertyRead)== CBCharacteristicPropertyRead) {
            if(![self.readChars containsObject:characteristic])
            {
                [self.readChars addObject:characteristic];
            }
        }
        
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(nullable NSError *)error {
    doInvokeResult *result = [[doInvokeResult alloc] init];
    if (error) {
        [result SetResultInteger:-1];
        [self asyncMethodCalllBackWithResult:result tipErrorString:nil];
        NSLog(@"%@",[NSString stringWithFormat:@"registerListener监听特征UUID: %@ 失败",characteristic.UUID.UUIDString]);
        [[doServiceContainer Instance].LogEngine WriteError:nil :[NSString stringWithFormat:@"registerListener监听特征UUID: %@ 失败",characteristic.UUID.UUIDString]];
    }else {
        [result SetResultInteger:0];
        [self asyncMethodCalllBackWithResult:result tipErrorString:nil];
    }
}

//监听特征值更新
- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    NSLog(@"可用特征更新...");
    if(error){
        NSLog(@"外围设备寻找服务过程中发生错误，错误信息：%@",error.localizedDescription);
    }
    
    if (self.haveReadCharacteristicUUIDArray.count > 0) {
        if ([self.haveReadCharacteristicUUIDArray containsObject:characteristic.UUID.UUIDString] && ((characteristic.properties & CBCharacteristicPropertyRead)== CBCharacteristicPropertyRead)) { // 当前特征UUID存储过，且特征为可读特征，说明正确的调用过read方法，这里处理read success的回调
            if (characteristic.value) { // value不为nil，说 明读取成功
                doInvokeResult *result = [[doInvokeResult alloc] init];
                [result SetResultInteger:0];
                [self asyncMethodCalllBackWithResult:result tipErrorString:nil];
            }else {
                doInvokeResult *result = [[doInvokeResult alloc] init];
                [result SetResultInteger:0];
                [self asyncMethodCalllBackWithResult:result tipErrorString:nil];
            }
        }
    }
    
    NSString *data = [[NSString alloc]initWithData:characteristic.value encoding:NSUTF8StringEncoding];

    
    //fire事件
    NSMutableDictionary *resDict = [NSMutableDictionary dictionary];
    //UUIDString 支持ios 7.1之后
    if (IOS_8) {
        [resDict setObject:characteristic.UUID.UUIDString forKey:@"uuid"];
    }
    if (!data) {
        data = @"";
    }
    [resDict setObject:data forKey:@"value"];
    doInvokeResult *invokeResult = [[doInvokeResult alloc]init];
    [invokeResult SetResultNode:resDict];
    [self.EventCenter FireEvent:@"characteristicChanged":invokeResult];
}

- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (error) {
        [[doServiceContainer Instance].LogEngine WriteInfo:@"write" :@"fail"];
    }
    else{
        [[doServiceContainer Instance].LogEngine WriteInfo:@"write" :@"success"];
    }
}
@end
