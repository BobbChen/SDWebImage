/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageCompat.h"
#import "SDWebImageDefine.h"
#import "SDWebImageManager.h"
#import "SDWebImageTransition.h"
#import "SDWebImageIndicator.h"
#import "UIView+WebCacheOperation.h"
#import "UIView+WebCacheState.h"

/**
 用来表示没有指定下载进度回调的单元个数
 */
FOUNDATION_EXPORT const int64_t SDWebImageProgressUnitCountUnknown; /* 1LL */

typedef void(^SDSetImageBlock)(UIImage * _Nullable image, NSData * _Nullable imageData, SDImageCacheType cacheType, NSURL * _Nullable imageURL);

/**
 将 SDWebImage 对远端图像的异步下载和缓存功能整合到UIView的子类
 */
@interface UIView (WebCache)

/**
 * 获取当前图片的操作键. 操作键用于识别对于同一个实例对象的不同查询 (比如 UIButton).
 * 更多的细节可以看 `SDWebImageContextSetImageOperationKey`.
 *
 * @note 可以使用`UIView+WebCacheOperation`中的方法去执行不同的查询方法
 * @note 为了能够和历史版本兼容，如果当前的`UIView`恰好有个属性命名为`image`，则这个操作键会使用`NSStringFromClass(self.class)`
 *
 * @warning 这个属性仅用于单状态视图,比如`UIImageView`
 */
@property (nonatomic, strong, readonly, nullable) NSString *sd_latestOperationKey;

#pragma mark - State

/**
 * 获取当前视图图片的链接url
 * 从v5.18.0版本开始这个属性只是`[self sd_imageLoadStateForKey:self.sd_latestOperationKey].url`的转换
 *
 * @note 因为分类的原因，如果直接调用`setImage:`方法这个属性可能不会同步
 * @warning 这个属性只适用于没有高亮状态的单状态视图比如`UIImageView`, 对于多状态视图比如`UIButton`使用`sd_imageLoadStateForKey:`方法获取对应信息
 */
@property (nonatomic, strong, readonly, nullable) NSURL *sd_imageURL;

/**
 * 视图关联的图片的下载进度，单位是已下载大小和图片的总大小，当新的图片开始下载的时候`totalUnitCount` 和 `completedUnitCount`会被重置为0。如果没有调用下载进度block那么图片下载完成后`totalUnitCount` 和 `completedUnitCount`会被设置为`SDWebImageProgressUnitCountUnknown`用来表示下载完成。
 * @note 可以使用KVO监听下载进度，但是需要注意下载进度的改变是在后台队列。如果想要通过KVO监听进度然后更新UI一定要保证是在主队列。更推荐使用`KVOController`这样会更安全
 *
 * @note 如果该属性为空则在进行获取的时候会创建实例，如果想要使用KVO监听，需要保证触发过该属性的Getter方法或者设置了一个自定义的progress实例对象。因为该值默认为空。
 *
 * @note 因为分类的限制如果直接更新此进度可能会不同步
 *
 * @warning 这个属性只适用于没有高亮状态的单状态视图比如`UIImageView`, 对于多状态视图比如`UIButton`使用`sd_imageLoadStateForKey:`方法获取对应信息
 *
 * @note `null_resettable` 标识该属性可以setter被置空，但是getter不能为空
 */
@property (nonatomic, strong, null_resettable) NSProgress *sd_imageProgress;

/**
 * 通过`url`设置图片以及可选的占位图图片
 *
 * 异步下载并带有缓存
 *
 * @param url            远端图片的url
 * @param placeholder    占位图会立即被设置直到远端图片被下载下来
 * @param options        这些选项在图片下载过程中会被用到. @see SDWebImageOptions 可用的选项
 * @param context        可以执行特殊操作的上下文选项, see `SDWebImageContextOption`上下文参数支持`SDWebImageOptions`不支持的额外操作
 * @param setImageBlock  用于自定义设置图片代码的block，如果没传则使用内置的设置图片代码
 * @param progressBlock  图片下载过程中会调用这个block
 *                       @note 这个block执行在后台队列
 *
 * @param completedBlock 当图片加载完成会调用这个block，这是一个无返回值有四个参数的block
 *                          第一个参数：通过url下载的图片
 *                          第二个参数：NSData形式的图片
 *                          第三个参数：下载出错的error
 *                          第四个参数：标识图片的来源（网络下载还是缓存数据）
 *                          第五个参数：标识是否下载完成的布尔值参数，通常是YES。但如果下载传入的option是`SDWebImageProgressiveLoad`渐进式下载，那么此block会频繁回调部分图片数据。当图片完整下载后这个block会最后回调一次带有完整图片的数据，此时为YES
 *                          第六个参数：图片的url
 *
 *  @return 该方法的返回值可以取消缓存和下载操作，通常情况下该类型为`SDWebImageCombinedOperation`
 */
- (nullable id<SDWebImageOperation>)sd_internalSetImageWithURL:(nullable NSURL *)url
                                              placeholderImage:(nullable UIImage *)placeholder
                                                       options:(SDWebImageOptions)options
                                                       context:(nullable SDWebImageContext *)context
                                                 setImageBlock:(nullable SDSetImageBlock)setImageBlock
                                                      progress:(nullable SDImageLoaderProgressBlock)progressBlock
                                                     completed:(nullable SDInternalCompletionBlock)completedBlock;

/**
 * 使用`sd_latestOperationKey`作为操作键，取消最新的图片加载操作
 * 这是`[self sd_cancelImageLoadOperationWithKey:self.sd_latestOperationKey]`方法的简单调用
 */
- (void)sd_cancelLatestImageLoad;

/**
 * 用于取消单状态视图的当前图片加载操作
 *
 * @warning 这个方法通常被用于像`UIImageView`这样的单状态视图. 对于`UIBtton`这样的多状态视图可以使用sd_cancelImageLoadOperationWithKey:`方法
 *
 * @deprecated 该方法会在V6.0版本移除，请使用`sd_cancelLatestImageLoad`
 */
- (void)sd_cancelCurrentImageLoad API_DEPRECATED_WITH_REPLACEMENT("sd_cancelLatestImageLoad", macos(10.10, 10.10), ios(8.0, 8.0), tvos(9.0, 9.0), watchos(2.0, 2.0));

#if SD_UIKIT || SD_MAC

#pragma mark - 图片过渡效果

/**
 图片加载完成进行显示的过渡效果，如果不指定则为空
 @warning 这个属性只适用于没有高亮状态的单状态视图比如`UIImageView`, 对于多状态视图比如`UIButton`使用`setImageBlock:`去添加自定义实现
 */
@property (nonatomic, strong, nullable) SDWebImageTransition *sd_imageTransition;

#pragma mark - 图片指示器

/**
 图片指示器用于图片加载过程中. 如果不需要则设置为空. 默认是空
 如果设置该属性将会移除旧的指示器并且添加新的指示器到当前视图的子视图中
 
 @note 因为是UI关联的属性，所以访问需要再主队列
 @warning  这个属性只适用于没有高亮状态的单状态视图比如`UIImageView`, 对于多状态视图比如`UIButton`使用`setImageBlock:`方法去添加自定义实现
 
 */
@property (nonatomic, strong, nullable) id<SDWebImageIndicator> sd_imageIndicator;

#endif

@end
