#import "tween.h"

@interface KineticTween () {
    NSView* _view;
    NSRect _startFrame;
    NSRect _endFrame;
    CGFloat _startAlpha;
    CGFloat _endAlpha;
    NSTimeInterval _startTime;
    NSTimeInterval _duration;
    NSTimer* _timer;
    KineticTweenCompletion _completion;
}
@end

@implementation KineticTween

+ (void)animateView:(NSView*)view
            toFrame:(NSRect)frame
            toAlpha:(CGFloat)alpha
           duration:(NSTimeInterval)duration
         completion:(KineticTweenCompletion)completion {
    KineticTween* tween = [[KineticTween alloc] init];
    tween->_view = view;
    tween->_startFrame = view.frame;
    tween->_endFrame = frame;
    tween->_startAlpha = view.alphaValue;
    tween->_endAlpha = alpha;
    tween->_startTime = NSProcessInfo.processInfo.systemUptime;
    tween->_duration = MAX(duration, 0.001);
    tween->_completion = [completion copy];
    tween->_timer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0
                                                     target:tween
                                                   selector:@selector(step:)
                                                   userInfo:nil
                                                    repeats:YES];
}

- (void)step:(NSTimer*)timer {
    NSTimeInterval elapsed = NSProcessInfo.processInfo.systemUptime - _startTime;
    CGFloat progress = MIN(1.0, elapsed / _duration);
    CGFloat inverse = 1.0 - progress;
    CGFloat eased = 1.0 - inverse * inverse * inverse;

    NSRect frame;
    frame.origin.x = _startFrame.origin.x + (_endFrame.origin.x - _startFrame.origin.x) * eased;
    frame.origin.y = _startFrame.origin.y + (_endFrame.origin.y - _startFrame.origin.y) * eased;
    frame.size.width =
        _startFrame.size.width + (_endFrame.size.width - _startFrame.size.width) * eased;
    frame.size.height =
        _startFrame.size.height + (_endFrame.size.height - _startFrame.size.height) * eased;
    _view.frame = frame;
    _view.alphaValue = _startAlpha + (_endAlpha - _startAlpha) * eased;

    if (progress >= 1.0) {
        [timer invalidate];
        _timer = nil;
        if (_completion != nil) {
            _completion();
            _completion = nil;
        }
    }
}

@end
