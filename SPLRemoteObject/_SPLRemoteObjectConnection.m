//
//  _SPLRemoteObjectConnection.m
//  SPLRemoteObject
//
//  The MIT License (MIT)
//  Copyright (c) 2013 Oliver Letterer, Sparrow-Labs
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#import "_SPLRemoteObjectConnection.h"
#import "SPLRemoteObject.h"
#import <Security/Security.h>
#import <Security/SecureTransport.h>

static BOOL streamIsHealthyAndOpen(NSStream *stream)
{
    NSStreamStatus streamStatus = stream.streamStatus;

    if (streamStatus == NSStreamStatusNotOpen || streamStatus == NSStreamStatusClosed || streamStatus == NSStreamStatusError) {
        return NO;
    } else {
        return YES;
    }
}


@interface _SPLRemoteObjectConnection () <NSStreamDelegate> {
    NSMutableData *_incomingDataBuffer;
    NSMutableData *_outgoingDataBuffer;

    int32_t _packetBodySize;
}

@property (nonatomic, readonly) BOOL isInputStreamOpen;
@property (nonatomic, readonly) BOOL isOutputStreamOpen;

@end



@implementation _SPLRemoteObjectConnection

#pragma mark - setters and getters

- (BOOL)isClientConnection
{
    [self doesNotRecognizeSelector:_cmd];
    return NO;
}

- (void)setInputStream:(NSInputStream *)inputStream
{
    if (inputStream != _inputStream) {
        _inputStream.delegate = nil;
        [_inputStream close];
        [_inputStream removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

        _inputStream = inputStream;

        _inputStream.delegate = self;
        [_inputStream scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        [_inputStream open];
    }
}

- (void)setOutputStream:(NSOutputStream *)outputStream
{
    if (outputStream != _outputStream) {
        _outputStream.delegate = nil;
        [_outputStream close];
        [_outputStream removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

        _outputStream = outputStream;

        _outputStream.delegate = self;
        [_outputStream scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        [_outputStream open];
    }
}

#pragma mark - Initialization

- (id)init
{
    if (self = [super init]) {
        _incomingDataBuffer = [NSMutableData dataWithCapacity:1024];
        _outgoingDataBuffer = [NSMutableData dataWithCapacity:1024];

        _packetBodySize = -1;
    }
    return self;
}

#pragma mark - Instance methods for connectivity

- (void)connect
{
    _isConnected = YES;

    [[NSNotificationCenter defaultCenter] postNotificationName:SPLRemoteObjectNetworkOperationDidStartNotification object:nil];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.isConnected) {
            [self disconnect];
            [self.delegate remoteObjectConnectionConnectionAttemptFailed:self];
        }
    });
}

- (void)disconnect
{
    if (!_isConnected) {
        return;
    }

    _isConnected = NO;

    [[NSNotificationCenter defaultCenter] postNotificationName:SPLRemoteObjectNetworkOperationDidEndNotification object:nil];

    self.inputStream = nil;
    self.outputStream = nil;

    [_incomingDataBuffer replaceBytesInRange:NSMakeRange(0, _incomingDataBuffer.length) withBytes:NULL length:0];
    [_outgoingDataBuffer replaceBytesInRange:NSMakeRange(0, _outgoingDataBuffer.length) withBytes:NULL length:0];
}

- (void)sendDataPackage:(NSData *)dataPackage
{
    int32_t length = (int32_t)dataPackage.length;

    [_outgoingDataBuffer appendBytes:&length length:sizeof(int32_t)];
    [_outgoingDataBuffer appendData:dataPackage];

    [self _sendNextChunkOfData];
}

#pragma mark - Memory management

- (void)dealloc
{
    [self disconnect];
}

#pragma mark - NSStreamDelegate

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
    if (aStream == self.inputStream) {
        [self _inputStreamHandleEventType:eventCode];
    } else if (aStream == self.outputStream) {
        [self _outputStreamHandleEventType:eventCode];
    }
}

#pragma mark - inputStream

- (void)_readNextChunkOfData
{
    uint8_t buffer[1024];

    size_t processed = 0;
    do {
        processed = [self _readDataFromReadStream:buffer length:sizeof(buffer)];
        [_incomingDataBuffer appendBytes:buffer length:processed];
    } while (processed > 0);

    while(YES) {
        if (_packetBodySize == -1) {
            if (_incomingDataBuffer.length >= sizeof(int32_t)) {
                memcpy(&_packetBodySize, _incomingDataBuffer.bytes, sizeof(int32_t));

                NSRange rangeToDelete = NSMakeRange(0, sizeof(int32_t));
                [_incomingDataBuffer replaceBytesInRange:rangeToDelete withBytes:NULL length:0];
            } else {
                break;
            }
        }

        if (_incomingDataBuffer.length >= _packetBodySize) {
            NSData *dataPackage = [_incomingDataBuffer subdataWithRange:NSMakeRange(0, _packetBodySize)];
            [_delegate remoteObjectConnection:self didReceiveDataPackage:dataPackage];

            NSRange rangeToDelete = NSMakeRange(0, MIN(_packetBodySize, _incomingDataBuffer.length));
            [_incomingDataBuffer replaceBytesInRange:rangeToDelete withBytes:NULL length:0];

            _packetBodySize = -1;
        } else {
            break;
        }
    }
}

- (void)_inputStreamHandleEventType:(NSStreamEvent)eventType
{
    if (eventType & NSStreamEventOpenCompleted) {
        _isInputStreamOpen = YES;
    } else if (eventType == NSStreamEventHasBytesAvailable) {
        [self _readNextChunkOfData];
    } else if (eventType == NSStreamEventErrorOccurred || eventType == NSStreamEventEndEncountered) {
        [self disconnect];

        // If we haven't connected yet then our connection attempt has failed
        if (!self.isInputStreamOpen) {
            [_delegate remoteObjectConnectionConnectionAttemptFailed:self];
        } else {
            [_delegate remoteObjectConnectionConnectionEnded:self];
        }
    }
}

#pragma mark - outputStream

- (void)_sendNextChunkOfData
{
    if (_outgoingDataBuffer.length == 0) {
        return;
    }

    size_t processed = processed = [self _writeDataToWriteStream:_outgoingDataBuffer.bytes length:_outgoingDataBuffer.length];
    
    NSRange range = NSMakeRange(0, processed);
    [_outgoingDataBuffer replaceBytesInRange:range withBytes:NULL length:0];
}

- (void)_outputStreamHandleEventType:(NSStreamEvent)eventType
{
    if (eventType == NSStreamEventOpenCompleted) {
        _isOutputStreamOpen = YES;
    } else if (eventType == NSStreamEventHasSpaceAvailable) {
        [self _sendNextChunkOfData];
    } else if (eventType == NSStreamEventEndEncountered || eventType == NSStreamEventErrorOccurred) {
        [self disconnect];

        if (!self.isOutputStreamOpen) {
            [_delegate remoteObjectConnectionConnectionAttemptFailed:self];
        } else {
            [_delegate remoteObjectConnectionConnectionEnded:self];
        }
    }
}

#pragma mark - SSLContext read and write hooks

- (size_t)_readDataFromReadStream:(void *)data length:(size_t)length
{
    if (!self.isInputStreamOpen || !self.inputStream.hasBytesAvailable || !streamIsHealthyAndOpen(self.inputStream)) {
        return 0;
    }

    NSInteger bytesRead = [self.inputStream read:data maxLength:length];

    if (length <= 0 || !streamIsHealthyAndOpen(self.inputStream)) {
        [self disconnect];
        [_delegate remoteObjectConnectionConnectionEnded:self];
        return 0;
    }

    return bytesRead;
}

- (size_t)_writeDataToWriteStream:(const void *)data length:(size_t)length
{
    if (!self.isOutputStreamOpen || !self.outputStream.hasSpaceAvailable || !streamIsHealthyAndOpen(self.outputStream)) {
        return 0;
    }

    NSInteger writtenBytes = [self.outputStream write:data maxLength:length];

    if (writtenBytes == -1 || !streamIsHealthyAndOpen(self.outputStream)) {
        [self disconnect];
        [_delegate remoteObjectConnectionConnectionEnded:self];
        return 0;
    }

    return writtenBytes;
}

@end
