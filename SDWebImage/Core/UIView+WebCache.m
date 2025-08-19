/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "UIView+WebCache.h"
#import "objc/runtime.h"
#import "UIView+WebCacheOperation.h"
#import "SDWebImageError.h"
#import "SDInternalMacros.h"
#import "SDWebImageTransitionInternal.h"
#import "SDImageCache.h"
#import "SDCallbackQueue.h"

const int64_t SDWebImageProgressUnitCountUnknown = 1LL;

@implementation UIView (WebCache)

// `sd_latestOperationKey`属性的getter方法，用关联属性的方式获取UIView的属性
- (nullable NSString *)sd_latestOperationKey {
    return objc_getAssociatedObject(self, @selector(sd_latestOperationKey));
}

// `sd_latestOperationKey`属性的setter方法，用关联属性的方式获取UIView的属性
- (void)setSd_latestOperationKey:(NSString * _Nullable)sd_latestOperationKey {
    objc_setAssociatedObject(self, @selector(sd_latestOperationKey), sd_latestOperationKey, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

#pragma mark - State

- (NSURL *)sd_imageURL {
    // 使用`sd_latestOperationKey`属性获取当前视图的图片url
    return [self sd_imageLoadStateForKey:self.sd_latestOperationKey].url;
}

// 获取图片加载的进度属性
- (NSProgress *)sd_imageProgress {
    SDWebImageLoadState *loadState = [self sd_imageLoadStateForKey:self.sd_latestOperationKey];
    NSProgress *progress = loadState.progress;
    if (!progress) {
        // 如果没有获取到，则构建一个
        progress = [[NSProgress alloc] initWithParent:nil userInfo:nil];
        self.sd_imageProgress = progress;
    }
    return progress;
}

- (void)setSd_imageProgress:(NSProgress *)sd_imageProgress {
    // 有效性校验
    if (!sd_imageProgress) {
        return;
    }
    // 通过操作键获取
    SDWebImageLoadState *loadState = [self sd_imageLoadStateForKey:self.sd_latestOperationKey];
    if (!loadState) {
        // 没有获取到初始话一个新的
        loadState = [SDWebImageLoadState new];
    }
    loadState.progress = sd_imageProgress;
    // 用操作键给当前视图设置加载状态属性
    [self sd_setImageLoadState:loadState forKey:self.sd_latestOperationKey];
}

// 通过图片链接给视图设置图片的方法
- (nullable id<SDWebImageOperation>)sd_internalSetImageWithURL:(nullable NSURL *)url
                                              placeholderImage:(nullable UIImage *)placeholder
                                                       options:(SDWebImageOptions)options
                                                       context:(nullable SDWebImageContext *)context
                                                 setImageBlock:(nullable SDSetImageBlock)setImageBlock
                                                      progress:(nullable SDImageLoaderProgressBlock)progressBlock
                                                     completed:(nullable SDInternalCompletionBlock)completedBlock {
    
    //  最常见的错误是url参数传递字符串而不是NSURL，这个问题xcode并不会抛出异常，所以这里我们允许url参数传入字符串类型
    //  如果url是字符串类型并且`shouldUseWeakMemoryCache`为true，那么调用`[cacheKeyForURL:context]`方法将会崩溃，所以这里进行专门的处理
    if ([url isKindOfClass:NSString.class]) {
        url = [NSURL URLWithString:(NSString *)url];
    }
    // 如果url不是`NSURL`类型，则置为空，保证不会崩溃
    if (![url isKindOfClass:NSURL.class]) {
        url = nil;
    }

    // 如果有上下文参数，进行一次copy，context本质是字典类型
    if (context) {
        // 进行一次copy避免context是可变类型
        context = [context copy];
    } else {
        // 外部没有传入，内部初始化一个空的上下文字典
        context = [NSDictionary dictionary];
    }
    
    NSString *validOperationKey = context[SDWebImageContextSetImageOperationKey];
    if (!validOperationKey) {
        // 把操作键传递给之后的流程，操作键可以跟踪对应的视图类
        // 根据当前视图类的类型生成字符串操作键
        validOperationKey = NSStringFromClass([self class]);
        SDWebImageMutableContext *mutableContext = [context mutableCopy];
        // 将操作键存入上下文字典中
        mutableContext[SDWebImageContextSetImageOperationKey] = validOperationKey;
        context = [mutableContext copy];
    }
    // 当前视图的操作键进行赋值
    self.sd_latestOperationKey = validOperationKey;
    
    // 外部调用该方法是否设置了避免自动取消上一个下载操作（当调用该方法后默认是取消上一个图片加载操作）
    if (!(SD_OPTIONS_CONTAINS(options, SDWebImageAvoidAutoCancelImage))) {
        // 如果外部没有设置，那么按照默认流程，先取消该视图的上一次图片加载操作
        [self sd_cancelImageLoadOperationWithKey:validOperationKey];
    }
    // 通过操作键获取加载状态
    SDWebImageLoadState *loadState = [self sd_imageLoadStateForKey:validOperationKey];
    if (!loadState) {
        // 没有初始化一个
        loadState = [SDWebImageLoadState new];
    }
    loadState.url = url;
    // 给当前视图设置加载状态属性
    [self sd_setImageLoadState:loadState forKey:validOperationKey];
    
    // 获取图片管理类
    SDWebImageManager *manager = context[SDWebImageContextCustomManager];
    if (!manager) {
        // 没有则初始化一个
        manager = [SDWebImageManager sharedManager];
    } else {
        // 如果有则移除掉，循环引用 (manger -> loader -> operation -> context -> manager)
        SDWebImageMutableContext *mutableContext = [context mutableCopy];
        mutableContext[SDWebImageContextCustomManager] = nil;
        context = [mutableContext copy];
    }
    
    // 图片加载完成后的回调队列
    SDCallbackQueue *queue = context[SDWebImageContextCallbackQueue];
    BOOL shouldUseWeakCache = NO;
    
    // 如果图片管理类内部的缓存管理属性代理是`SDImageCache`的实例
    if ([manager.imageCache isKindOfClass:SDImageCache.class]) {
        shouldUseWeakCache = ((SDImageCache *)manager.imageCache).config.shouldUseWeakMemoryCache;
    }
    
    // 如果是占位图立刻展示模式（(options & SDWebImageDelayPlaceholder)为false）
    if (!(options & SDWebImageDelayPlaceholder)) {
        if (shouldUseWeakCache) {
            // 调用manager的方法生成缓存键
            NSString *key = [manager cacheKeyForURL:url context:context];
            
            // 调用内存缓存方法来触发弱缓存的同步逻辑，忽略该方法的返回值
            // 这将触发两次内存缓存查询，后期再优化
            [((SDImageCache *)manager.imageCache) imageFromMemoryCacheForKey:key];
        }
        
        // 如果上下文参数不包含回调队列，则使用主队列去进行后续的图片设置操作
        [(queue ?: SDCallbackQueue.mainQueue) async:^{
            [self sd_setImage:placeholder imageData:nil basedOnClassOrViaCustomSetImageBlock:setImageBlock cacheType:SDImageCacheTypeNone imageURL:url];
        }];
    }
    
    // 构建可用于取消图片加载的操作对象
    id <SDWebImageOperation> operation = nil;
    
    if (url) {
        // 重置图片下载进度
        NSProgress *imageProgress = loadState.progress;
        if (imageProgress) {
            imageProgress.totalUnitCount = 0;
            imageProgress.completedUnitCount = 0;
        }
        
#if SD_UIKIT || SD_MAC
        // iOS/tvOS/visionOS/Mac平台下，检查并开始加载指示器
        [self sd_startImageIndicatorWithQueue:queue];
        id<SDWebImageIndicator> imageIndicator = self.sd_imageIndicator;
#endif
        
        // 下载进度block
        SDImageLoaderProgressBlock combinedProgressBlock = ^(NSInteger receivedSize, NSInteger expectedSize, NSURL * _Nullable targetURL) {
            // 给`SDWebImageLoadState`设置进度值
            if (imageProgress) {
                imageProgress.totalUnitCount = expectedSize;
                imageProgress.completedUnitCount = receivedSize;
            }
#if SD_UIKIT || SD_MAC
            // / iOS/tvOS/visionOS/Mac平台下更新进度指示器UI
            if ([imageIndicator respondsToSelector:@selector(updateIndicatorProgress:)]) {
                double progress = 0;
                if (expectedSize != 0) {
                    // 计算已下载的百分比
                    progress = (double)receivedSize / expectedSize;
                }
                // 确保百分比是0.0 - 1.0范围内
                progress = MAX(MIN(progress, 1), 0); // 0.0 - 1.0
                dispatch_async(dispatch_get_main_queue(), ^{
                    // 主线程刷新UI
                    [imageIndicator updateIndicatorProgress:progress];
                });
            }
#endif
            // 外部调用有进度回调的话，将进度信息回调给最外部的调用者
            if (progressBlock) {
                progressBlock(receivedSize, expectedSize, targetURL);
            }
        };
        
        // 使用`SDWebImageManager`的方法初始化`SDWebImageOperation`实例
        @weakify(self);
        operation = [manager loadImageWithURL:url options:options context:context progress:combinedProgressBlock completed:^(UIImage *image, NSData *data, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
            @strongify(self);
            if (!self) { return; }
            // if the progress not been updated, mark it to complete state
            if (imageProgress && finished && !error && imageProgress.totalUnitCount == 0 && imageProgress.completedUnitCount == 0) {
                imageProgress.totalUnitCount = SDWebImageProgressUnitCountUnknown;
                imageProgress.completedUnitCount = SDWebImageProgressUnitCountUnknown;
            }
            
#if SD_UIKIT || SD_MAC
            // check and stop image indicator
            if (finished) {
                [self sd_stopImageIndicatorWithQueue:queue];
            }
#endif
            
            BOOL shouldCallCompletedBlock = finished || (options & SDWebImageAvoidAutoSetImage);
            BOOL shouldNotSetImage = ((image && (options & SDWebImageAvoidAutoSetImage)) ||
                                      (!image && !(options & SDWebImageDelayPlaceholder)));
            SDWebImageNoParamsBlock callCompletedBlockClosure = ^{
                if (!self) { return; }
                if (!shouldNotSetImage) {
                    [self sd_setNeedsLayout];
                }
                if (completedBlock && shouldCallCompletedBlock) {
                    completedBlock(image, data, error, cacheType, finished, url);
                }
            };
            
            // case 1a: we got an image, but the SDWebImageAvoidAutoSetImage flag is set
            // OR
            // case 1b: we got no image and the SDWebImageDelayPlaceholder is not set
            if (shouldNotSetImage) {
                [(queue ?: SDCallbackQueue.mainQueue) async:callCompletedBlockClosure];
                return;
            }
            
            UIImage *targetImage = nil;
            NSData *targetData = nil;
            if (image) {
                // case 2a: we got an image and the SDWebImageAvoidAutoSetImage is not set
                targetImage = image;
                targetData = data;
            } else if (options & SDWebImageDelayPlaceholder) {
                // case 2b: we got no image and the SDWebImageDelayPlaceholder flag is set
                targetImage = placeholder;
                targetData = nil;
            }
            
#if SD_UIKIT || SD_MAC
            // check whether we should use the image transition
            SDWebImageTransition *transition = nil;
            BOOL shouldUseTransition = NO;
            if (options & SDWebImageForceTransition) {
                // Always
                shouldUseTransition = YES;
            } else if (cacheType == SDImageCacheTypeNone) {
                // From network
                shouldUseTransition = YES;
            } else {
                // From disk (and, user don't use sync query)
                if (cacheType == SDImageCacheTypeMemory) {
                    shouldUseTransition = NO;
                } else if (cacheType == SDImageCacheTypeDisk) {
                    if (options & SDWebImageQueryMemoryDataSync || options & SDWebImageQueryDiskDataSync) {
                        shouldUseTransition = NO;
                    } else {
                        shouldUseTransition = YES;
                    }
                } else {
                    // Not valid cache type, fallback
                    shouldUseTransition = NO;
                }
            }
            if (finished && shouldUseTransition) {
                transition = self.sd_imageTransition;
            }
#endif
            [(queue ?: SDCallbackQueue.mainQueue) async:^{
#if SD_UIKIT || SD_MAC
                [self sd_setImage:targetImage imageData:targetData options:options basedOnClassOrViaCustomSetImageBlock:setImageBlock transition:transition cacheType:cacheType imageURL:imageURL callback:callCompletedBlockClosure];
#else
                [self sd_setImage:targetImage imageData:targetData basedOnClassOrViaCustomSetImageBlock:setImageBlock cacheType:cacheType imageURL:imageURL];
                callCompletedBlockClosure();
#endif
            }];
        }];
        [self sd_setImageLoadOperation:operation forKey:validOperationKey];
    } else {
#if SD_UIKIT || SD_MAC
        [self sd_stopImageIndicatorWithQueue:queue];
#endif
        if (completedBlock) {
            [(queue ?: SDCallbackQueue.mainQueue) async:^{
                NSError *error = [NSError errorWithDomain:SDWebImageErrorDomain code:SDWebImageErrorInvalidURL userInfo:@{NSLocalizedDescriptionKey : @"Image url is nil"}];
                completedBlock(nil, nil, error, SDImageCacheTypeNone, YES, url);
            }];
        }
    }
    
    return operation;
}

- (void)sd_cancelLatestImageLoad {
    [self sd_cancelImageLoadOperationWithKey:self.sd_latestOperationKey];
}

- (void)sd_cancelCurrentImageLoad {
    [self sd_cancelImageLoadOperationWithKey:self.sd_latestOperationKey];
}

// Set image logic without transition (like placeholder and watchOS)
- (void)sd_setImage:(UIImage *)image imageData:(NSData *)imageData basedOnClassOrViaCustomSetImageBlock:(SDSetImageBlock)setImageBlock cacheType:(SDImageCacheType)cacheType imageURL:(NSURL *)imageURL {
#if SD_UIKIT || SD_MAC
    [self sd_setImage:image imageData:imageData options:0 basedOnClassOrViaCustomSetImageBlock:setImageBlock transition:nil cacheType:cacheType imageURL:imageURL callback:nil];
#else
    // watchOS does not support view transition. Simplify the logic
    if (setImageBlock) {
        setImageBlock(image, imageData, cacheType, imageURL);
    } else if ([self isKindOfClass:[UIImageView class]]) {
        UIImageView *imageView = (UIImageView *)self;
        [imageView setImage:image];
    }
#endif
}

// Set image logic with transition
#if SD_UIKIT || SD_MAC
- (void)sd_setImage:(UIImage *)image imageData:(NSData *)imageData options:(SDWebImageOptions)options basedOnClassOrViaCustomSetImageBlock:(SDSetImageBlock)setImageBlock transition:(SDWebImageTransition *)transition cacheType:(SDImageCacheType)cacheType imageURL:(NSURL *)imageURL callback:(SDWebImageNoParamsBlock)callback {
    UIView *view = self;
    SDSetImageBlock finalSetImageBlock;
    if (setImageBlock) {
        finalSetImageBlock = setImageBlock;
    } else if ([view isKindOfClass:[UIImageView class]]) {
        UIImageView *imageView = (UIImageView *)view;
        finalSetImageBlock = ^(UIImage *setImage, NSData *setImageData, SDImageCacheType setCacheType, NSURL *setImageURL) {
            imageView.image = setImage;
        };
    }
#if SD_UIKIT
    else if ([view isKindOfClass:[UIButton class]]) {
        UIButton *button = (UIButton *)view;
        finalSetImageBlock = ^(UIImage *setImage, NSData *setImageData, SDImageCacheType setCacheType, NSURL *setImageURL) {
            [button setImage:setImage forState:UIControlStateNormal];
        };
    }
#endif
#if SD_MAC
    else if ([view isKindOfClass:[NSButton class]]) {
        NSButton *button = (NSButton *)view;
        finalSetImageBlock = ^(UIImage *setImage, NSData *setImageData, SDImageCacheType setCacheType, NSURL *setImageURL) {
            button.image = setImage;
        };
    }
#endif
    
    BOOL waitTransition = SD_OPTIONS_CONTAINS(options, SDWebImageWaitTransition);
    if (transition) {
        NSString *originalOperationKey = view.sd_latestOperationKey;

#if SD_UIKIT
        [UIView transitionWithView:view duration:0 options:0 animations:^{
            if (!view.sd_latestOperationKey || ![originalOperationKey isEqualToString:view.sd_latestOperationKey]) {
                return;
            }
            // 0 duration to let UIKit render placeholder and prepares block
            if (transition.prepares) {
                transition.prepares(view, image, imageData, cacheType, imageURL);
            }
        } completion:^(BOOL tempFinished) {
            [UIView transitionWithView:view duration:transition.duration options:transition.animationOptions animations:^{
                if (!view.sd_latestOperationKey || ![originalOperationKey isEqualToString:view.sd_latestOperationKey]) {
                    return;
                }
                if (finalSetImageBlock && !transition.avoidAutoSetImage) {
                    finalSetImageBlock(image, imageData, cacheType, imageURL);
                }
                if (transition.animations) {
                    transition.animations(view, image);
                }
            } completion:^(BOOL finished) {
                if (!view.sd_latestOperationKey || ![originalOperationKey isEqualToString:view.sd_latestOperationKey]) {
                    return;
                }
                if (transition.completion) {
                    transition.completion(finished);
                }
                if (waitTransition) {
                    if (callback) {
                        callback();
                    }
                }
            }];
        }];
#elif SD_MAC
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull prepareContext) {
            if (!view.sd_latestOperationKey || ![originalOperationKey isEqualToString:view.sd_latestOperationKey]) {
                return;
            }
            // 0 duration to let AppKit render placeholder and prepares block
            prepareContext.duration = 0;
            if (transition.prepares) {
                transition.prepares(view, image, imageData, cacheType, imageURL);
            }
        } completionHandler:^{
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
                if (!view.sd_latestOperationKey || ![originalOperationKey isEqualToString:view.sd_latestOperationKey]) {
                    return;
                }
                context.duration = transition.duration;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                CAMediaTimingFunction *timingFunction = transition.timingFunction;
#pragma clang diagnostic pop
                if (!timingFunction) {
                    timingFunction = SDTimingFunctionFromAnimationOptions(transition.animationOptions);
                }
                context.timingFunction = timingFunction;
                context.allowsImplicitAnimation = SD_OPTIONS_CONTAINS(transition.animationOptions, SDWebImageAnimationOptionAllowsImplicitAnimation);
                if (finalSetImageBlock && !transition.avoidAutoSetImage) {
                    finalSetImageBlock(image, imageData, cacheType, imageURL);
                }
                CATransition *trans = SDTransitionFromAnimationOptions(transition.animationOptions);
                if (trans) {
                    [view.layer addAnimation:trans forKey:kCATransition];
                }
                if (transition.animations) {
                    transition.animations(view, image);
                }
            } completionHandler:^{
                if (!view.sd_latestOperationKey || ![originalOperationKey isEqualToString:view.sd_latestOperationKey]) {
                    return;
                }
                if (transition.completion) {
                    transition.completion(YES);
                }
                if (waitTransition) {
                    if (callback) {
                        callback();
                    }
                }
            }];
        }];
#endif
        if (!waitTransition) {
            if (callback) {
                callback();
            }
        }
    } else {
        if (finalSetImageBlock) {
            finalSetImageBlock(image, imageData, cacheType, imageURL);
            // TODO, in 6.0
            // for `waitTransition`, the `setImageBlock` will provide a extra `completionHandler` params
            // Execute `callback` only after that completionHandler is called
            if (waitTransition) {
                if (callback) {
                    callback();
                }
            }
        }
        if (!waitTransition) {
            if (callback) {
                callback();
            }
        }
    }
}
#endif

- (void)sd_setNeedsLayout {
#if SD_UIKIT
    [self setNeedsLayout];
#elif SD_MAC
    [self setNeedsLayout:YES];
#elif SD_WATCH
    // Do nothing because WatchKit automatically layout the view after property change
#endif
}

#if SD_UIKIT || SD_MAC

#pragma mark - Image Transition
- (SDWebImageTransition *)sd_imageTransition {
    return objc_getAssociatedObject(self, @selector(sd_imageTransition));
}

- (void)setSd_imageTransition:(SDWebImageTransition *)sd_imageTransition {
    objc_setAssociatedObject(self, @selector(sd_imageTransition), sd_imageTransition, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - Indicator
- (id<SDWebImageIndicator>)sd_imageIndicator {
    return objc_getAssociatedObject(self, @selector(sd_imageIndicator));
}

- (void)setSd_imageIndicator:(id<SDWebImageIndicator>)sd_imageIndicator {
    // Remove the old indicator view
    id<SDWebImageIndicator> previousIndicator = self.sd_imageIndicator;
    [previousIndicator.indicatorView removeFromSuperview];
    
    objc_setAssociatedObject(self, @selector(sd_imageIndicator), sd_imageIndicator, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    // Add the new indicator view
    UIView *view = sd_imageIndicator.indicatorView;
    if (CGRectEqualToRect(view.frame, CGRectZero)) {
        view.frame = self.bounds;
    }
    // Center the indicator view
#if SD_MAC
    [view setFrameOrigin:CGPointMake(round((NSWidth(self.bounds) - NSWidth(view.frame)) / 2), round((NSHeight(self.bounds) - NSHeight(view.frame)) / 2))];
#else
    view.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
#endif
    view.hidden = NO;
    [self addSubview:view];
}


/// 开始加载指示器
/// - Parameter queue: 队列
- (void)sd_startImageIndicatorWithQueue:(SDCallbackQueue *)queue {
    
    // 如果自身没有指示器就跳出
    id<SDWebImageIndicator> imageIndicator = self.sd_imageIndicator;
    if (!imageIndicator) {
        return;
    }
    // 没有传入队列则在主队列执行指示器动画
    [(queue ?: SDCallbackQueue.mainQueue) async:^{
        [imageIndicator startAnimatingIndicator];
    }];
}

- (void)sd_stopImageIndicatorWithQueue:(SDCallbackQueue *)queue {
    id<SDWebImageIndicator> imageIndicator = self.sd_imageIndicator;
    if (!imageIndicator) {
        return;
    }
    [(queue ?: SDCallbackQueue.mainQueue) async:^{
        [imageIndicator stopAnimatingIndicator];
    }];
}

#endif

@end
