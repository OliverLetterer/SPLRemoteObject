//
//  _SPLRemoteObjectConnection.h
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

@class _SPLRemoteObjectConnection;

@protocol _SPLRemoteObjectConnectionDelegate <NSObject>

- (void)remoteObjectConnectionConnectionAttemptFailed:(_SPLRemoteObjectConnection *)connection;
- (void)remoteObjectConnectionConnectionEnded:(_SPLRemoteObjectConnection *)connection;

- (void)remoteObjectConnection:(_SPLRemoteObjectConnection *)connection didReceiveDataPackage:(NSData *)dataPackage;

@end



/**
 @abstract  <#abstract comment#>
 */
@interface _SPLRemoteObjectConnection : NSObject

@property (nonatomic, strong) NSInputStream *inputStream;
@property (nonatomic, strong) NSOutputStream *outputStream;

@property (nonatomic, readonly) BOOL isClientConnection;

@property (nonatomic, weak) id<_SPLRemoteObjectConnectionDelegate> delegate;

@property (nonatomic, assign) BOOL SSLEnabled;

/**
 optional for client connections, can only accept connection to peer with valid domain name
 */
@property (nonatomic, strong) NSString *peerDomainName;

/**
 required for server connections
 */
@property (nonatomic, assign) SecIdentityRef identity;

@property (nonatomic, readonly) BOOL isConnected;

- (void)connect;
- (void)disconnect;

- (void)sendDataPackage:(NSData *)dataPackage;

@end
