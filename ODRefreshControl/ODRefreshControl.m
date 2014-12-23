//
//  ODRefreshControl.m
//  ODRefreshControl
//
//  Created by Fabio Ritrovato on 6/13/12.
//  Copyright (c) 2012 orange in a day. All rights reserved.
//
// https://github.com/Sephiroth87/ODRefreshControl
//

#import "ODRefreshControl.h"

#define kTotalViewHeight    400
#define kOpenedViewHeight   50
#define kMinTopPadding      9
#define kMaxTopPadding      5
#define kMinTopRadius       12.5
#define kMaxTopRadius       16
#define kMinBottomRadius    3
#define kMaxBottomRadius    16
#define kMinBottomPadding   4
#define kMaxBottomPadding   6
#define kMinArrowSize       2
#define kMaxArrowSize       3
#define kMinArrowRadius     5
#define kMaxArrowRadius     7
#define kMaxDistance        53

@interface ODRefreshControl ()

@property (nonatomic, readwrite) BOOL refreshing;
@property (nonatomic, assign) UIScrollView *scrollView;
@property (nonatomic, assign) UIEdgeInsets originalContentInset;

@end

@implementation ODRefreshControl

@synthesize refreshing = _refreshing;
@synthesize tintColor = _tintColor;

@synthesize scrollView = _scrollView;
@synthesize originalContentInset = _originalContentInset;

static inline CGFloat lerp(CGFloat a, CGFloat b, CGFloat p)
{
    return a + (b - a) * p;
}

- (id)initInScrollView:(UIScrollView *)scrollView {
    return [self initInScrollView:scrollView activityIndicatorView:nil];
}

- (id)initInScrollView:(UIScrollView *)scrollView activityIndicatorView:(UIView *)activity
{
    self = [super initWithFrame:CGRectMake(-(kOpenedViewHeight + scrollView.contentInset.left), 0, kOpenedViewHeight, scrollView.frame.size.height)];
    
    if (self) {
        self.scrollView = scrollView;
        self.originalContentInset = scrollView.contentInset;
        
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [scrollView addSubview:self];
        [scrollView addObserver:self forKeyPath:@"contentOffset" options:NSKeyValueObservingOptionNew context:nil];
        [scrollView addObserver:self forKeyPath:@"contentInset" options:NSKeyValueObservingOptionNew context:nil];
        
        _activity = activity ? activity : [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        _activity.center = CGPointMake(floor(self.frame.size.width / 2), floor(self.frame.size.height / 2));
        _activity.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
        _activity.alpha = 0;
        if ([_activity respondsToSelector:@selector(startAnimating)]) {
            [(UIActivityIndicatorView *)_activity startAnimating];
        }
        [self addSubview:_activity];
        
        _refreshing = NO;
        _canRefresh = YES;
        _ignoreInset = NO;
        _ignoreOffset = NO;
        _didSetInset = NO;
        _hasSectionHeaders = NO;
        _tintColor = [UIColor colorWithRed:155.0 / 255.0 green:162.0 / 255.0 blue:172.0 / 255.0 alpha:1.0];
        
        _shapeLayer = [CAShapeLayer layer];
        _shapeLayer.fillColor = [_tintColor CGColor];
        _shapeLayer.strokeColor = [[[UIColor darkGrayColor] colorWithAlphaComponent:0.5] CGColor];
        _shapeLayer.lineWidth = 0.5;
        _shapeLayer.shadowColor = [[UIColor blackColor] CGColor];
        _shapeLayer.shadowOffset = CGSizeMake(0, 1);
        _shapeLayer.shadowOpacity = 0.4;
        _shapeLayer.shadowRadius = 0.5;
        [self.layer addSublayer:_shapeLayer];
        
        _arrowLayer = [CAShapeLayer layer];
        _arrowLayer.strokeColor = [[[UIColor darkGrayColor] colorWithAlphaComponent:0.5] CGColor];
        _arrowLayer.lineWidth = 0.5;
        _arrowLayer.fillColor = [[UIColor whiteColor] CGColor];
        [_shapeLayer addSublayer:_arrowLayer];
        
        _highlightLayer = [CAShapeLayer layer];
        _highlightLayer.fillColor = [[[UIColor whiteColor] colorWithAlphaComponent:0.2] CGColor];
        [_shapeLayer addSublayer:_highlightLayer];
    }
    return self;
}

- (void)dealloc
{
    [self.scrollView removeObserver:self forKeyPath:@"contentOffset"];
    [self.scrollView removeObserver:self forKeyPath:@"contentInset"];
    self.scrollView = nil;
}

- (void)setEnabled:(BOOL)enabled
{
    super.enabled = enabled;
    _shapeLayer.hidden = !self.enabled;
}

- (void)willMoveToSuperview:(UIView *)newSuperview
{
    [super willMoveToSuperview:newSuperview];
    if (!newSuperview) {
        [self.scrollView removeObserver:self forKeyPath:@"contentOffset"];
        [self.scrollView removeObserver:self forKeyPath:@"contentInset"];
        self.scrollView = nil;
    }
}

- (void)setTintColor:(UIColor *)tintColor
{
    _tintColor = tintColor;
    _shapeLayer.fillColor = [_tintColor CGColor];
}

- (void)setActivityIndicatorViewStyle:(UIActivityIndicatorViewStyle)activityIndicatorViewStyle
{
    if ([_activity isKindOfClass:[UIActivityIndicatorView class]]) {
        [(UIActivityIndicatorView *)_activity setActivityIndicatorViewStyle:activityIndicatorViewStyle];
    }
}

- (UIActivityIndicatorViewStyle)activityIndicatorViewStyle
{
    if ([_activity isKindOfClass:[UIActivityIndicatorView class]]) {
        return [(UIActivityIndicatorView *)_activity activityIndicatorViewStyle];
    }
    return 0;
}

- (void)setActivityIndicatorViewColor:(UIColor *)activityIndicatorViewColor
{
    if ([_activity isKindOfClass:[UIActivityIndicatorView class]] && [_activity respondsToSelector:@selector(setColor:)]) {
        [(UIActivityIndicatorView *)_activity setColor:activityIndicatorViewColor];
    }
}

- (UIColor *)activityIndicatorViewColor
{
    if ([_activity isKindOfClass:[UIActivityIndicatorView class]] && [_activity respondsToSelector:@selector(color)]) {
        return [(UIActivityIndicatorView *)_activity color];
    }
    return nil;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath isEqualToString:@"contentInset"]) {
        return;
    }
    
    if (!self.enabled || _ignoreOffset) {
        return;
    }

    CGPoint contentOffset = [[change objectForKey:@"new"] CGPointValue];
    CGFloat offsetInset = contentOffset.x;
    CGFloat deltaOffset = offsetInset;
    bool refreshIsObscured = (deltaOffset >= 0);
    
    if (_refreshing) {
        
        [CATransaction begin];
        [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
        _shapeLayer.position = CGPointMake(kMaxDistance + deltaOffset + kOpenedViewHeight, 0);
        [CATransaction commit];
        
        CGFloat halfWidth = self.frame.size.width * 0.5f;
        CGFloat x1 = halfWidth + deltaOffset + self.frame.size.width;
        CGFloat x2 = halfWidth;
        
        // within point of refresh
        if (deltaOffset < 0)
        {
            if (!self.scrollView.dragging) {
                [self.scrollView setContentInset:UIEdgeInsetsMake(self.originalContentInset.top, self.originalContentInset.left + kOpenedViewHeight, self.originalContentInset.bottom, self.originalContentInset.right + 0)];
                [self.scrollView setContentOffset:CGPointMake(-kOpenedViewHeight, self.scrollView.contentOffset.y) animated:false];
                x1 = x2;
            }
        }
        
        _activity.center = CGPointMake(MIN(x1, x2), self.frame.size.height / 2);
        
        return;
    } else {
        // Check if we can trigger a new refresh and if we can draw the control
        BOOL dontDraw = NO;
        if (!_canRefresh) {
            if (refreshIsObscured) {
                // We can refresh again after the control is scrolled out of view
                _canRefresh = YES;
                _didSetInset = NO;
            } else {
                dontDraw = YES;
            }
        } else {
            if (refreshIsObscured) {
                // Don't draw if the control is not visible
                dontDraw = YES;
            }
        }
        if (deltaOffset > 0 && _lastOffset > deltaOffset && !self.scrollView.isTracking) {
            // If we are scrolling too fast, don't draw, and don't trigger unless the scrollView bounced back
            _canRefresh = NO;
            dontDraw = YES;
        }
        if (dontDraw) {
            _shapeLayer.path = nil;
            _shapeLayer.shadowPath = nil;
            _arrowLayer.path = nil;
            _highlightLayer.path = nil;
            _lastOffset = deltaOffset;
            return;
        }
    }
    
    _lastOffset = deltaOffset;
    
    BOOL triggered = NO;
    
    CGMutablePathRef path = CGPathCreateMutable();
    
    //Calculate some useful points and values
    CGFloat verticalShift = MAX(0, -((kMaxTopRadius + kMaxBottomRadius + kMaxTopPadding + kMaxBottomPadding) + deltaOffset));
    CGFloat distance = MIN(kMaxDistance, fabs(verticalShift));
    CGFloat percentage = 1 - (distance / kMaxDistance);
    CGFloat currentLeftPadding = lerp(kMinTopPadding, kMaxTopPadding, percentage);
    CGFloat currentLeftRadius = lerp(kMinTopRadius, kMaxTopRadius, percentage);
    CGFloat currentRightRadius = lerp(kMinBottomRadius, kMaxBottomRadius, percentage);
    CGFloat currentRightPadding =  lerp(kMinBottomPadding, kMaxBottomPadding, percentage);
    
    CGFloat halfHeight = floor(self.bounds.size.height / 2);
    
    CGPoint rightOrigin = CGPointMake(self.bounds.size.width - currentRightPadding -currentRightRadius, halfHeight);
    CGPoint leftOrigin = CGPointZero;
    
        if (distance == 0) {
            leftOrigin = CGPointMake( rightOrigin.x, halfHeight);
        } else {
            leftOrigin = CGPointMake(self.bounds.size.width + deltaOffset + currentLeftPadding + currentLeftRadius, halfHeight);
            if (percentage == 0) {
                rightOrigin.x -= (fabs(verticalShift) - kMaxDistance);
                triggered = YES;
            }
        }
        
        //Left cemicircle
        CGPathAddArc(path, NULL, leftOrigin.x, leftOrigin.y, currentLeftRadius, -M_PI/2.0f, M_PI / 2.0f, YES);
        
        // Bottom curve
        CGPoint bottomCp1 = CGPointMake(lerp(leftOrigin.x, rightOrigin.x, .2f), lerp ((leftOrigin.y + currentLeftRadius), (rightOrigin.y + currentRightRadius), .1f));
        CGPoint bottomCp2 = CGPointMake(lerp (leftOrigin.x, rightOrigin.x, .2f), lerp ((leftOrigin.y + currentLeftRadius), (rightOrigin.y + currentRightRadius), .9f));
        CGPoint bottomDestination = CGPointMake(rightOrigin.x, rightOrigin.y + currentRightRadius);
        
        CGPathAddCurveToPoint(path, NULL, bottomCp1.x, bottomCp1.y, bottomCp2.x, bottomCp2.y, bottomDestination.x, bottomDestination.y);
        
        //Right semicircle
        CGPathAddArc(path, NULL, rightOrigin.x, rightOrigin.y, currentRightRadius, M_PI/2.0f, 3 * M_PI / 2.0f, YES);
        
        //Top curve
        CGPoint topCp2 = CGPointMake(lerp (leftOrigin.x, rightOrigin.x, .2f), lerp ((leftOrigin.y - currentLeftRadius), (rightOrigin.y - currentRightRadius), .1f));
        CGPoint topCp1 = CGPointMake(lerp (leftOrigin.x, rightOrigin.x, .2f), lerp ((leftOrigin.y - currentLeftRadius), (rightOrigin.y - currentRightRadius), .9f));
        CGPoint topDestination = CGPointMake(leftOrigin.x, leftOrigin.y - currentLeftRadius);
        
        CGPathAddCurveToPoint(path, NULL, topCp1.x, topCp1.y, topCp2.x, topCp2.y, topDestination.x, topDestination.y);
    
    CGPathCloseSubpath(path);
    
    if (!triggered) {
        // Set paths
        
        _shapeLayer.path = path;
        _shapeLayer.shadowPath = path;
        
        // Add the arrow shape
        
        CGFloat currentArrowSize = lerp(kMinArrowSize, kMaxArrowSize, percentage);
        CGFloat currentArrowRadius = lerp(kMinArrowRadius, kMaxArrowRadius, percentage);
        CGFloat arrowBigRadius = currentArrowRadius + (currentArrowSize / 2);
        CGFloat arrowSmallRadius = currentArrowRadius - (currentArrowSize / 2);
        CGMutablePathRef arrowPath = CGPathCreateMutable();
        CGPathAddArc(arrowPath, NULL, leftOrigin.x, leftOrigin.y, arrowBigRadius, 0, 3 * M_PI_2, NO);
        CGPathAddLineToPoint(arrowPath, NULL, leftOrigin.x, leftOrigin.y - arrowBigRadius - currentArrowSize);
        CGPathAddLineToPoint(arrowPath, NULL, leftOrigin.x + (2 * currentArrowSize), leftOrigin.y - arrowBigRadius + (currentArrowSize / 2));
        CGPathAddLineToPoint(arrowPath, NULL, leftOrigin.x, leftOrigin.y - arrowBigRadius + (2 * currentArrowSize));
        CGPathAddLineToPoint(arrowPath, NULL, leftOrigin.x, leftOrigin.y - arrowBigRadius + currentArrowSize);
        CGPathAddArc(arrowPath, NULL, leftOrigin.x, leftOrigin.y, arrowSmallRadius, 3 * M_PI_2, 0, YES);
        CGPathCloseSubpath(arrowPath);
        _arrowLayer.path = arrowPath;
        [_arrowLayer setFillRule:kCAFillRuleEvenOdd];
        CGPathRelease(arrowPath);
        
        // Add the highlight shape
        
        CGMutablePathRef highlightPath = CGPathCreateMutable();
        CGPathAddArc(highlightPath, NULL, leftOrigin.x, leftOrigin.y, currentLeftRadius, - M_PI / 2.0f, M_PI / 2.0f, YES);
        CGPathAddArc(highlightPath, NULL, leftOrigin.x + 1.25f, leftOrigin.y, currentLeftRadius, M_PI / 2.0f, - M_PI / 2.0f, NO);
        
        _highlightLayer.path = highlightPath;
        [_highlightLayer setFillRule:kCAFillRuleNonZero];
        CGPathRelease(highlightPath);
        
    } else {
        // Start the shape disappearance animation
        
        CGFloat radius = lerp(kMinBottomRadius, kMaxBottomRadius, 0.2);
        CABasicAnimation *pathMorph = [CABasicAnimation animationWithKeyPath:@"path"];
        pathMorph.duration = 0.15;
        pathMorph.fillMode = kCAFillModeForwards;
        pathMorph.removedOnCompletion = NO;
        CGMutablePathRef toPath = CGPathCreateMutable();
        CGPathAddArc(toPath, NULL, leftOrigin.x, leftOrigin.y, radius, 0, M_PI, YES);
        CGPathAddCurveToPoint(toPath, NULL, leftOrigin.x - radius, leftOrigin.y, leftOrigin.x - radius, leftOrigin.y, leftOrigin.x - radius, leftOrigin.y);
        CGPathAddArc(toPath, NULL, leftOrigin.x, leftOrigin.y, radius, M_PI, 0, YES);
        CGPathAddCurveToPoint(toPath, NULL, leftOrigin.x + radius, leftOrigin.y, leftOrigin.x + radius, leftOrigin.y, leftOrigin.x + radius, leftOrigin.y);
        CGPathCloseSubpath(toPath);
        pathMorph.toValue = (__bridge id)toPath;
        [_shapeLayer addAnimation:pathMorph forKey:nil];
        CABasicAnimation *shadowPathMorph = [CABasicAnimation animationWithKeyPath:@"shadowPath"];
        shadowPathMorph.duration = 0.15;
        shadowPathMorph.fillMode = kCAFillModeForwards;
        shadowPathMorph.removedOnCompletion = NO;
        shadowPathMorph.toValue = (__bridge id)toPath;
        [_shapeLayer addAnimation:shadowPathMorph forKey:nil];
        CGPathRelease(toPath);
        CABasicAnimation *shapeAlphaAnimation = [CABasicAnimation animationWithKeyPath:@"opacity"];
        shapeAlphaAnimation.duration = 0.1;
        shapeAlphaAnimation.beginTime = CACurrentMediaTime() + 0.1;
        shapeAlphaAnimation.toValue = [NSNumber numberWithFloat:0];
        shapeAlphaAnimation.fillMode = kCAFillModeForwards;
        shapeAlphaAnimation.removedOnCompletion = NO;
        [_shapeLayer addAnimation:shapeAlphaAnimation forKey:nil];
        CABasicAnimation *alphaAnimation = [CABasicAnimation animationWithKeyPath:@"opacity"];
        alphaAnimation.duration = 0.1;
        alphaAnimation.toValue = [NSNumber numberWithFloat:0];
        alphaAnimation.fillMode = kCAFillModeForwards;
        alphaAnimation.removedOnCompletion = NO;
        [_arrowLayer addAnimation:alphaAnimation forKey:nil];
        [_highlightLayer addAnimation:alphaAnimation forKey:nil];
        
        [CATransaction begin];
        [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
        _activity.layer.transform = CATransform3DMakeScale(0.1, 0.1, 1);
        [CATransaction commit];
        [UIView animateWithDuration:0.2 delay:0.15 options:UIViewAnimationOptionCurveLinear animations:^{
            _activity.alpha = 1;
            _activity.layer.transform = CATransform3DMakeScale(1, 1, 1);
        } completion:nil];
        
        self.refreshing = YES;
        _canRefresh = NO;
        [self sendActionsForControlEvents:UIControlEventValueChanged];
    }
    
    CGPathRelease(path);
}

- (void)beginRefreshing
{
    if (_refreshing)
        return;
    
    CABasicAnimation *alphaAnimation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    alphaAnimation.duration = 0.0001;
    alphaAnimation.toValue = [NSNumber numberWithFloat:0];
    alphaAnimation.fillMode = kCAFillModeForwards;
    alphaAnimation.removedOnCompletion = NO;
    [_shapeLayer addAnimation:alphaAnimation forKey:nil];
    [_arrowLayer addAnimation:alphaAnimation forKey:nil];
    [_highlightLayer addAnimation:alphaAnimation forKey:nil];
    
    _activity.alpha = 1;
    _activity.layer.transform = CATransform3DMakeScale(1, 1, 1);
    
    CGPoint offset = self.scrollView.contentOffset;
    _ignoreInset = YES;
    [self.scrollView setContentInset:UIEdgeInsetsMake(kOpenedViewHeight + self.originalContentInset.top, self.originalContentInset.left, self.originalContentInset.bottom, self.originalContentInset.right)];
    _ignoreInset = NO;
    [self.scrollView setContentOffset:offset animated:NO];
    
    self.refreshing = YES;
    _canRefresh = NO;
}

- (void)endRefreshing
{
    if (_refreshing == false)
        return;
    self.refreshing = NO;
    // Create a temporary retain-cycle, so the scrollView won't be released
    // halfway through the end animation.
    // This allows for the refresh control to clean up the observer,
    // in the case the scrollView is released while the animation is running
    __block UIScrollView *blockScrollView = self.scrollView;
    [blockScrollView setContentInset:self.originalContentInset];
    [UIView animateWithDuration:0.4 animations:^{
        _ignoreInset = YES;
        _ignoreInset = NO;
        _activity.alpha = 0;
        _activity.layer.transform = CATransform3DMakeScale(0.1, 0.1, 1);

    } completion:^(BOOL finished) {
        [_shapeLayer removeAllAnimations];
        _shapeLayer.path = nil;
        _shapeLayer.shadowPath = nil;
        _shapeLayer.position = CGPointZero;
        [_arrowLayer removeAllAnimations];
        _arrowLayer.path = nil;
        [_highlightLayer removeAllAnimations];
        _highlightLayer.path = nil;
        // We need to use the scrollView somehow in the end block,
        // or it'll get released in the animation block.
        blockScrollView = blockScrollView;
        _ignoreInset = YES;
        _ignoreInset = NO;
    }];
}

@end
