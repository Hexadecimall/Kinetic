#pragma once

#import <AppKit/AppKit.h>

typedef void (^KineticTweenCompletion)(void);

@interface KineticTween : NSObject
+ (void)animateView:(NSView*)view
            toFrame:(NSRect)frame
            toAlpha:(CGFloat)alpha
           duration:(NSTimeInterval)duration
         completion:(KineticTweenCompletion)completion;
@end
