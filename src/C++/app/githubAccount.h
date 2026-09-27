#pragma once

#import <Foundation/Foundation.h>

@class NSImage;

typedef NS_ENUM(NSInteger, KineticGitHubAccountPhase) {
    KineticGitHubAccountPhaseSignedOut,
    KineticGitHubAccountPhaseRequestingCode,
    KineticGitHubAccountPhaseAwaitingApproval,
    KineticGitHubAccountPhaseLoadingProfile,
    KineticGitHubAccountPhaseSignedIn,
    KineticGitHubAccountPhaseError,
};

@class KineticGitHubAccount;

@protocol KineticGitHubAccountDelegate <NSObject>
- (void)githubAccountDidChange:(KineticGitHubAccount*)account;
@end

@interface KineticGitHubAccount : NSObject
@property(nonatomic, weak) id<KineticGitHubAccountDelegate> delegate;
@property(nonatomic, readonly) KineticGitHubAccountPhase phase;
@property(nonatomic, readonly, copy) NSString* login;
@property(nonatomic, readonly, copy) NSString* displayName;
@property(nonatomic, readonly, strong) NSImage* avatarImage;
@property(nonatomic, readonly, copy) NSString* userCode;
@property(nonatomic, readonly, copy) NSString* statusText;
@property(nonatomic, readonly) BOOL signInAvailable;
- (instancetype)initWithClientId:(NSString*)clientId;
- (instancetype)initWithClientId:(NSString*)clientId
                         session:(NSURLSession*)session
                 keychainService:(NSString*)keychainService;
- (void)restoreSession;
- (void)startSignIn;
- (void)openVerificationPage;
- (void)cancelSignIn;
- (void)signOut;
@end
