/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import <Foundation/Foundation.h>
#import "SDWebImageCompat.h"

/**
 用于管理视图分类的加载状态，比如`UIImgeView.image` 和 `UIImageView.highlightedImage`

 * @code
    SDWebImageLoadState *loadState = [self sd_imageLoadStateForKey:@keypath(self, highlitedImage)];
    NSProgress *highlitedImageProgress = loadState.progress;
 * @endcode
 */
@interface SDWebImageLoadState : NSObject

/**
 当前状态下对应的下载URL
 */
@property (nonatomic, strong, nullable) NSURL *url;
/**
 图片资源下载进度. 包含已下载的大小和图片资源总大小信息
 */
@property (nonatomic, strong, nullable) NSProgress *progress;

@end

/**
 These methods are used for WebCache view which have multiple states for image loading, for example, `UIButton` or `UIImageView.highlightedImage`
 It maitain the state container for per-operation, make it possible for control and check each image loading operation's state.
 @note For developer who want to add SDWebImage View Category support for their own stateful class, learn more on Wiki.
 */
@interface UIView (WebCacheState)

/**
 Get the image loading state container for specify operation key

 @param key key for identifying the operations
 @return The image loading state container
 */
- (nullable SDWebImageLoadState *)sd_imageLoadStateForKey:(nullable NSString *)key;

/**
 Set the image loading state container for specify operation key

 @param state The image loading state container
 @param key key for identifying the operations
 */
- (void)sd_setImageLoadState:(nullable SDWebImageLoadState *)state forKey:(nullable NSString *)key;

/**
 Rmove the image loading state container for specify operation key

 @param key key for identifying the operations
 */
- (void)sd_removeImageLoadStateForKey:(nullable NSString *)key;

@end
