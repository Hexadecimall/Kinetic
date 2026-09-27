#import "githubAccount.h"

#import <AppKit/AppKit.h>
#import <Security/Security.h>

namespace {

NSString* const kDefaultKeychainService = @"top.frameworksdev.kinetic.github";
NSString* const kKeychainAccount = @"activeAccount";
NSString* const kVerificationUrl = @"https://github.com/login/device";

NSData* formBody(NSArray<NSURLQueryItem*>* items) {
    NSURLComponents* components = [[NSURLComponents alloc] init];
    components.queryItems = items;
    return [components.percentEncodedQuery dataUsingEncoding:NSUTF8StringEncoding];
}

NSString* textValue(id value) {
    return [value isKindOfClass:NSString.class] ? value : nil;
}

NSNumber* numberValue(id value) {
    return [value isKindOfClass:NSNumber.class] ? value : nil;
}

} // namespace

@interface KineticGitHubAccount ()
@property(nonatomic, copy) NSString* clientId;
@property(nonatomic, copy) NSString* keychainService;
@property(nonatomic, strong) NSURLSession* session;
@property(nonatomic) KineticGitHubAccountPhase phase;
@property(nonatomic, copy) NSString* login;
@property(nonatomic, copy) NSString* displayName;
@property(nonatomic, strong) NSImage* avatarImage;
@property(nonatomic, copy) NSString* userCode;
@property(nonatomic, copy) NSString* statusText;
@property(nonatomic, copy) NSString* deviceCode;
@property(nonatomic, copy) NSString* accessToken;
@property(nonatomic, copy) NSString* refreshToken;
@property(nonatomic, strong) NSDate* accessExpiresAt;
@property(nonatomic, strong) NSDate* refreshExpiresAt;
@property(nonatomic, strong) NSDate* deviceExpiresAt;
@property(nonatomic) NSTimeInterval pollInterval;
@property(nonatomic) NSUInteger flowGeneration;
@end

@implementation KineticGitHubAccount

- (instancetype)initWithClientId:(NSString*)clientId {
    return [self initWithClientId:clientId session:nil keychainService:kDefaultKeychainService];
}

- (instancetype)initWithClientId:(NSString*)clientId
                         session:(NSURLSession*)session
                 keychainService:(NSString*)keychainService {
    self = [super init];
    if (self) {
        _clientId = [clientId copy] ?: @"";
        _keychainService = [keychainService copy] ?: kDefaultKeychainService;
        _phase = KineticGitHubAccountPhaseSignedOut;
        _statusText = @"Sign in to connect a GitHub account.";
        NSURLSessionConfiguration* configuration =
            NSURLSessionConfiguration.ephemeralSessionConfiguration;
        configuration.URLCache = nil;
        configuration.HTTPCookieStorage = nil;
        _session = session ?: [NSURLSession sessionWithConfiguration:configuration];
    }
    return self;
}

- (BOOL)signInAvailable {
    return self.clientId.length > 0;
}

- (void)notifyChange {
    [self.delegate githubAccountDidChange:self];
}

- (void)showError:(NSString*)message {
    self.phase = KineticGitHubAccountPhaseError;
    self.statusText = message;
    self.userCode = nil;
    self.deviceCode = nil;
    [self notifyChange];
}

- (NSMutableDictionary*)keychainQuery {
    return [@{
        (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService : self.keychainService,
        (__bridge id)kSecAttrAccount : kKeychainAccount,
    } mutableCopy];
}

- (BOOL)saveSession {
    if (self.accessToken.length == 0) {
        return NO;
    }
    NSDictionary* sessionData = @{
        @"accessToken" : self.accessToken,
        @"refreshToken" : self.refreshToken ?: @"",
        @"login" : self.login ?: @"",
        @"displayName" : self.displayName ?: @"",
        @"accessExpiresAt" : @([self.accessExpiresAt timeIntervalSince1970]),
        @"refreshExpiresAt" : @([self.refreshExpiresAt timeIntervalSince1970]),
    };
    NSData* data = [NSJSONSerialization dataWithJSONObject:sessionData options:0 error:nil];
    if (data == nil) {
        return NO;
    }
    NSMutableDictionary* query = [self keychainQuery];
    OSStatus result = SecItemCopyMatching((__bridge CFDictionaryRef)query, nullptr);
    if (result == errSecSuccess) {
        return SecItemUpdate((__bridge CFDictionaryRef)query,
                             (__bridge CFDictionaryRef)
                                 @{(__bridge id)kSecValueData : data}) == errSecSuccess;
    }
    query[(__bridge id)kSecValueData] = data;
    query[(__bridge id)kSecAttrAccessible] =
        (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
    return SecItemAdd((__bridge CFDictionaryRef)query, nullptr) == errSecSuccess;
}

- (void)clearSession {
    SecItemDelete((__bridge CFDictionaryRef)[self keychainQuery]);
    self.login = nil;
    self.displayName = nil;
    self.avatarImage = nil;
    self.accessToken = nil;
    self.refreshToken = nil;
    self.accessExpiresAt = nil;
    self.refreshExpiresAt = nil;
}

- (void)restoreSession {
    NSMutableDictionary* query = [self keychainQuery];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    NSUInteger generation = self.flowGeneration;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
      CFTypeRef result = nullptr;
      OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
      NSData* data = result == nullptr ? nil : CFBridgingRelease(result);
      dispatch_async(dispatch_get_main_queue(), ^{
        if (self.flowGeneration != generation ||
            self.phase != KineticGitHubAccountPhaseSignedOut) {
            return;
        }
        if (status == errSecItemNotFound) {
            return;
        }
        if (status != errSecSuccess || data == nil) {
            [self showError:@"Could not read the saved GitHub session from Keychain."];
            return;
        }
        NSDictionary* stored = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![stored isKindOfClass:NSDictionary.class] ||
            textValue(stored[@"accessToken"]).length == 0) {
            [self clearSession];
            return;
        }
        self.accessToken = textValue(stored[@"accessToken"]);
        self.refreshToken = textValue(stored[@"refreshToken"]);
        self.login = textValue(stored[@"login"]);
        self.displayName = textValue(stored[@"displayName"]);
        self.accessExpiresAt = [NSDate
            dateWithTimeIntervalSince1970:numberValue(stored[@"accessExpiresAt"]).doubleValue];
        self.refreshExpiresAt = [NSDate
            dateWithTimeIntervalSince1970:numberValue(stored[@"refreshExpiresAt"]).doubleValue];
        self.phase = KineticGitHubAccountPhaseLoadingProfile;
        self.statusText = @"Checking GitHub session…";
        [self notifyChange];
        if (self.accessExpiresAt.timeIntervalSince1970 > 0 &&
            [self.accessExpiresAt timeIntervalSinceNow] < 60.0) {
            [self refreshSession];
        } else {
            [self loadProfileAllowingRefresh:YES];
        }
      });
    });
}

- (void)sendRequest:(NSURLRequest*)request
         completion:
             (void (^)(NSDictionary* response, NSInteger statusCode, NSError* error))completion {
    [[self.session dataTaskWithRequest:request
                     completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
                       NSDictionary* json = nil;
                       if (data.length > 0) {
                           id parsed = [NSJSONSerialization JSONObjectWithData:data
                                                                       options:0
                                                                         error:nil];
                           if ([parsed isKindOfClass:NSDictionary.class]) {
                               json = parsed;
                           }
                       }
                       NSInteger statusCode = [response isKindOfClass:NSHTTPURLResponse.class]
                                                  ? ((NSHTTPURLResponse*)response).statusCode
                                                  : 0;
                       dispatch_async(dispatch_get_main_queue(), ^{
                         completion(json, statusCode, error);
                       });
                     }] resume];
}

- (NSMutableURLRequest*)githubPost:(NSString*)path items:(NSArray<NSURLQueryItem*>*)items {
    NSURL* url = [NSURL URLWithString:[@"https://github.com" stringByAppendingString:path]];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.HTTPBody = formBody(items);
    request.timeoutInterval = 20.0;
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    return request;
}

- (void)startSignIn {
    if (!self.signInAvailable) {
        [self showError:@"GitHub sign-in is not configured in this build."];
        return;
    }
    if (self.phase == KineticGitHubAccountPhaseRequestingCode ||
        self.phase == KineticGitHubAccountPhaseAwaitingApproval) {
        return;
    }
    [self clearSession];
    NSUInteger generation = ++self.flowGeneration;
    self.phase = KineticGitHubAccountPhaseRequestingCode;
    self.statusText = @"Requesting a sign-in code from GitHub…";
    [self notifyChange];

    NSMutableURLRequest* request =
        [self githubPost:@"/login/device/code"
                   items:@[
                       [NSURLQueryItem queryItemWithName:@"client_id" value:self.clientId],
                       [NSURLQueryItem queryItemWithName:@"scope" value:@"repo offline_access"],
                   ]];
    [self sendRequest:request
           completion:^(NSDictionary* response, NSInteger statusCode, NSError* error) {
             if (generation != self.flowGeneration) {
                 return;
             }
             NSString* deviceCode = textValue(response[@"device_code"]);
             NSString* userCode = textValue(response[@"user_code"]);
             NSString* verificationUrl = textValue(response[@"verification_uri"]);
             if (error != nil || statusCode != 200 || deviceCode.length == 0 ||
                 userCode.length == 0 || ![verificationUrl isEqualToString:kVerificationUrl]) {
                 [self showError:@"Could not start GitHub sign-in. Try again."];
                 return;
             }
             self.deviceCode = deviceCode;
             self.userCode = userCode;
             self.pollInterval = MAX(5.0, numberValue(response[@"interval"]).doubleValue);
             NSTimeInterval lifetime = MAX(0.0, numberValue(response[@"expires_in"]).doubleValue);
             self.deviceExpiresAt = [NSDate dateWithTimeIntervalSinceNow:lifetime];
             self.phase = KineticGitHubAccountPhaseAwaitingApproval;
             self.statusText = @"Enter this code on GitHub to finish signing in.";
             [self notifyChange];
             [self schedulePoll:generation];
           }];
}

- (void)openVerificationPage {
    if (self.phase == KineticGitHubAccountPhaseAwaitingApproval) {
        [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:kVerificationUrl]];
    }
}

- (void)schedulePoll:(NSUInteger)generation {
    NSTimeInterval delay = self.pollInterval;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                     if (generation == self.flowGeneration &&
                         self.phase == KineticGitHubAccountPhaseAwaitingApproval) {
                         [self pollForToken:generation];
                     }
                   });
}

- (void)pollForToken:(NSUInteger)generation {
    if ([self.deviceExpiresAt timeIntervalSinceNow] <= 0.0) {
        [self showError:@"The sign-in code expired. Start again for a new code."];
        return;
    }
    NSMutableURLRequest* request = [self
        githubPost:@"/login/oauth/access_token"
             items:@[
                 [NSURLQueryItem queryItemWithName:@"client_id" value:self.clientId],
                 [NSURLQueryItem queryItemWithName:@"device_code" value:self.deviceCode],
                 [NSURLQueryItem queryItemWithName:@"grant_type"
                                             value:@"urn:ietf:params:oauth:grant-type:device_code"],
             ]];
    [self sendRequest:request
           completion:^(NSDictionary* response, NSInteger statusCode, NSError* error) {
             if (generation != self.flowGeneration) {
                 return;
             }
             if (error != nil || statusCode == 0 || statusCode >= 500) {
                 self.statusText = @"Waiting for GitHub connection…";
                 [self notifyChange];
                 [self schedulePoll:generation];
                 return;
             }
             if (statusCode != 200) {
                 [self showError:@"GitHub sign-in could not be completed. Try again."];
                 return;
             }
             NSString* accessToken = textValue(response[@"access_token"]);
             if (accessToken.length > 0) {
                 NSArray<NSString*>* grantedScopes =
                     [textValue(response[@"scope"]) componentsSeparatedByString:@","];
                 if (![grantedScopes containsObject:@"repo"]) {
                     [self showError:@"Repository access was not granted. Sign in again to allow "
                                     @"Git integration."];
                     return;
                 }
                 self.accessToken = accessToken;
                 self.refreshToken = textValue(response[@"refresh_token"]);
                 NSTimeInterval accessLifetime = numberValue(response[@"expires_in"]).doubleValue;
                 NSTimeInterval refreshLifetime =
                     numberValue(response[@"refresh_token_expires_in"]).doubleValue;
                 self.accessExpiresAt = accessLifetime > 0
                                            ? [NSDate dateWithTimeIntervalSinceNow:accessLifetime]
                                            : nil;
                 self.refreshExpiresAt = refreshLifetime > 0
                                             ? [NSDate dateWithTimeIntervalSinceNow:refreshLifetime]
                                             : nil;
                 self.userCode = nil;
                 self.deviceCode = nil;
                 self.phase = KineticGitHubAccountPhaseLoadingProfile;
                 self.statusText = @"Loading GitHub profile…";
                 [self notifyChange];
                 [self loadProfileAllowingRefresh:NO];
                 return;
             }
             NSString* code = textValue(response[@"error"]);
             if ([code isEqualToString:@"authorization_pending"]) {
                 [self schedulePoll:generation];
             } else if ([code isEqualToString:@"slow_down"]) {
                 self.pollInterval =
                     MAX(self.pollInterval + 5.0, numberValue(response[@"interval"]).doubleValue);
                 [self schedulePoll:generation];
             } else if ([code isEqualToString:@"expired_token"]) {
                 [self showError:@"The sign-in code expired. Start again for a new code."];
             } else if ([code isEqualToString:@"access_denied"]) {
                 [self showError:@"GitHub sign-in was cancelled."];
             } else {
                 [self showError:@"GitHub rejected the sign-in request."];
             }
           }];
}

- (void)loadProfileAllowingRefresh:(BOOL)allowRefresh {
    if (self.accessToken.length == 0) {
        [self showError:@"No GitHub session is available."];
        return;
    }
    NSMutableURLRequest* request =
        [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://api.github.com/user"]];
    request.timeoutInterval = 20.0;
    [request setValue:[@"Bearer " stringByAppendingString:self.accessToken]
        forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"2022-11-28" forHTTPHeaderField:@"X-GitHub-Api-Version"];
    NSUInteger generation = self.flowGeneration;
    [self sendRequest:request
           completion:^(NSDictionary* response, NSInteger statusCode, NSError* error) {
             if (generation != self.flowGeneration) {
                 return;
             }
             if (statusCode == 401 && allowRefresh && self.refreshToken.length > 0) {
                 [self refreshSession];
                 return;
             }
             if (statusCode == 401) {
                 [self clearSession];
                 [self showError:@"GitHub session expired. Sign in again."];
                 return;
             }
             NSString* login = textValue(response[@"login"]);
             if (error == nil && statusCode == 200 && login.length > 0 &&
                 numberValue(response[@"id"]) != nil) {
                 self.login = login;
                 self.displayName = textValue(response[@"name"]);
                 if (![self saveSession]) {
                     [self clearSession];
                     [self showError:@"Could not save the GitHub session to Keychain."];
                     return;
                 }
                 self.phase = KineticGitHubAccountPhaseSignedIn;
                 self.statusText = @"Connected to GitHub.";
                 [self notifyChange];
                 [self loadAvatar:textValue(response[@"avatar_url"]) generation:generation];
             } else if (self.login.length > 0 && error != nil) {
                 self.phase = KineticGitHubAccountPhaseSignedIn;
                 self.statusText = @"Offline. Saved GitHub session is available.";
                 [self notifyChange];
             } else {
                 [self showError:@"Could not load the GitHub account. Try again."];
             }
           }];
}

- (void)loadAvatar:(NSString*)avatarUrl generation:(NSUInteger)generation {
    NSURLComponents* components = [NSURLComponents componentsWithString:avatarUrl];
    if (![components.scheme isEqualToString:@"https"] ||
        ![components.host isEqualToString:@"avatars.githubusercontent.com"] ||
        components.user != nil || components.password != nil || components.port != nil) {
        return;
    }
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:components.URL];
    request.timeoutInterval = 15.0;
    [[self.session dataTaskWithRequest:request
                     completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
                       if (error != nil || data.length == 0 || data.length > 1024 * 1024 ||
                           ![response.MIMEType hasPrefix:@"image/"]) {
                           return;
                       }
                       dispatch_async(dispatch_get_main_queue(), ^{
                         NSImage* avatar = [[NSImage alloc] initWithData:data];
                         if (generation == self.flowGeneration &&
                             self.phase == KineticGitHubAccountPhaseSignedIn && avatar.isValid) {
                             self.avatarImage = avatar;
                             [self notifyChange];
                         }
                       });
                     }] resume];
}

- (void)refreshSession {
    if (self.refreshToken.length == 0 || (self.refreshExpiresAt.timeIntervalSince1970 > 0 &&
                                          [self.refreshExpiresAt timeIntervalSinceNow] <= 0.0)) {
        [self clearSession];
        [self showError:@"GitHub session expired. Sign in again."];
        return;
    }
    NSMutableURLRequest* request =
        [self githubPost:@"/login/oauth/access_token"
                   items:@[
                       [NSURLQueryItem queryItemWithName:@"client_id" value:self.clientId],
                       [NSURLQueryItem queryItemWithName:@"grant_type" value:@"refresh_token"],
                       [NSURLQueryItem queryItemWithName:@"refresh_token" value:self.refreshToken],
                   ]];
    NSUInteger generation = self.flowGeneration;
    [self sendRequest:request
           completion:^(NSDictionary* response, NSInteger statusCode, NSError* error) {
             if (generation != self.flowGeneration) {
                 return;
             }
             if (error != nil || statusCode == 0 || statusCode >= 500) {
                 self.phase = KineticGitHubAccountPhaseSignedIn;
                 self.statusText = @"Offline. Saved GitHub session is available.";
                 [self notifyChange];
                 return;
             }
             NSString* token = textValue(response[@"access_token"]);
             if (statusCode != 200 || token.length == 0) {
                 [self clearSession];
                 [self showError:@"GitHub session expired. Sign in again."];
                 return;
             }
             self.accessToken = token;
             self.refreshToken = textValue(response[@"refresh_token"]);
             self.accessExpiresAt = [NSDate
                 dateWithTimeIntervalSinceNow:numberValue(response[@"expires_in"]).doubleValue];
             self.refreshExpiresAt = [NSDate
                 dateWithTimeIntervalSinceNow:numberValue(response[@"refresh_token_expires_in"])
                                                  .doubleValue];
             if (![self saveSession]) {
                 [self clearSession];
                 [self showError:@"Could not save the GitHub session to Keychain."];
                 return;
             }
             [self loadProfileAllowingRefresh:NO];
           }];
}

- (void)cancelSignIn {
    ++self.flowGeneration;
    self.userCode = nil;
    self.deviceCode = nil;
    self.phase = KineticGitHubAccountPhaseSignedOut;
    self.statusText = @"Sign in to connect a GitHub account.";
    [self notifyChange];
}

- (void)signOut {
    ++self.flowGeneration;
    [self clearSession];
    self.userCode = nil;
    self.deviceCode = nil;
    self.phase = KineticGitHubAccountPhaseSignedOut;
    self.statusText = @"Signed out on this device.";
    [self notifyChange];
}

@end
