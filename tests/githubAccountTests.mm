#import "githubAccount.h"

#import <Foundation/Foundation.h>

@interface KineticMockGitHubProtocol : NSURLProtocol
@property(class, nonatomic, copy) NSString* responseBody;
@property(class, nonatomic, copy) NSURLRequest* lastRequest;
@property(class, nonatomic, copy) NSString* lastBody;
@end

@implementation KineticMockGitHubProtocol

static NSString* mockResponseBody;
static NSURLRequest* mockLastRequest;
static NSString* mockLastBody;

+ (NSString*)responseBody {
    return mockResponseBody;
}

+ (void)setResponseBody:(NSString*)responseBody {
    mockResponseBody = [responseBody copy];
}

+ (NSURLRequest*)lastRequest {
    return mockLastRequest;
}

+ (void)setLastRequest:(NSURLRequest*)lastRequest {
    mockLastRequest = [lastRequest copy];
}

+ (NSString*)lastBody {
    return mockLastBody;
}

+ (void)setLastBody:(NSString*)lastBody {
    mockLastBody = [lastBody copy];
}

+ (BOOL)canInitWithRequest:(NSURLRequest*)request {
    return [request.URL.host isEqualToString:@"github.com"];
}

+ (NSURLRequest*)canonicalRequestForRequest:(NSURLRequest*)request {
    return request;
}

- (void)startLoading {
    KineticMockGitHubProtocol.lastRequest = self.request;
    NSData* body = self.request.HTTPBody;
    if (body == nil && self.request.HTTPBodyStream != nil) {
        NSInputStream* stream = self.request.HTTPBodyStream;
        [stream open];
        NSMutableData* streamed = [NSMutableData data];
        uint8_t buffer[1024];
        NSInteger count = 0;
        while ((count = [stream read:buffer maxLength:sizeof(buffer)]) > 0) {
            [streamed appendBytes:buffer length:(NSUInteger)count];
        }
        [stream close];
        body = streamed;
    }
    KineticMockGitHubProtocol.lastBody =
        [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
    NSData* data = [KineticMockGitHubProtocol.responseBody dataUsingEncoding:NSUTF8StringEncoding];
    NSHTTPURLResponse* response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                                              statusCode:200
                                                             HTTPVersion:@"HTTP/1.1"
                                                            headerFields:@{ @"Content-Type" : @"application/json" }];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {
}

@end

static void require(BOOL condition, NSString* message) {
    if (!condition) {
        fprintf(stderr, "%s\n", message.UTF8String);
        exit(1);
    }
}

static void waitForPhase(KineticGitHubAccount* account, KineticGitHubAccountPhase phase) {
    NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
    while (account.phase != phase && [deadline timeIntervalSinceNow] > 0) {
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                              beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    require(account.phase == phase, @"GitHub account did not reach expected phase");
}

static KineticGitHubAccount* testAccount(void) {
    NSURLSessionConfiguration* configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.protocolClasses = @[ KineticMockGitHubProtocol.class ];
    NSURLSession* session = [NSURLSession sessionWithConfiguration:configuration];
    return [[KineticGitHubAccount alloc] initWithClientId:@"Iv1.testClient"
                                                 session:session
                                         keychainService:@"top.frameworksdev.kinetic.github.test"];
}

int main(void) {
    @autoreleasepool {
        KineticGitHubAccount* unconfigured = [[KineticGitHubAccount alloc] initWithClientId:@""];
        require(!unconfigured.signInAvailable, @"Missing client ID must disable sign-in");
        [unconfigured startSignIn];
        require(unconfigured.phase == KineticGitHubAccountPhaseError,
                @"Missing client ID must show a configuration error");

        KineticMockGitHubProtocol.responseBody =
            @"{\"device_code\":\"testDevice\",\"user_code\":\"ABCD-1234\","
             "\"verification_uri\":\"https://github.com/login/device\","
             "\"expires_in\":900,\"interval\":5}";
        KineticGitHubAccount* account = testAccount();
        [account startSignIn];
        waitForPhase(account, KineticGitHubAccountPhaseAwaitingApproval);
        require([account.userCode isEqualToString:@"ABCD-1234"],
                @"Device code must be visible to the user");
        require([KineticMockGitHubProtocol.lastBody containsString:@"scope=repo%20offline_access"],
                @"Device request must ask for repository access and expiring tokens");
        [account cancelSignIn];
        require(account.phase == KineticGitHubAccountPhaseSignedOut,
                @"Cancel must stop an in-progress sign-in");

        KineticMockGitHubProtocol.responseBody =
            @"{\"device_code\":\"testDevice\",\"user_code\":\"ABCD-1234\","
             "\"verification_uri\":\"https://example.invalid/login/device\","
             "\"expires_in\":900,\"interval\":5}";
        KineticGitHubAccount* invalid = testAccount();
        [invalid startSignIn];
        waitForPhase(invalid, KineticGitHubAccountPhaseError);
        require(invalid.userCode.length == 0,
                @"An untrusted verification URL must never expose a sign-in code");
    }
    return 0;
}
