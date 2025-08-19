/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageCompat.h"
#import "SDWebImageManager.h"

/**
 * Usage with a UITableViewCell sub-class:
 *
 * @code

#import <SDWebImage/UIImageView+WebCache.h>

...

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *MyIdentifier = @"MyIdentifier";
 
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:MyIdentifier];
 
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:MyIdentifier];
    }
 
    // Here we use the provided sd_setImageWithURL:placeholderImage: method to load the web image
    // Ensure you use a placeholder image otherwise cells will be initialized with no image
    [cell.imageView sd_setImageWithURL:[NSURL URLWithString:@"http://example.com/image.jpg"]
                      placeholderImage:[UIImage imageNamed:@"placeholder"]];
 
    cell.textLabel.text = @"My Text";
    return cell;
}

 * @endcode
 */

/**
 * 将SDWebImage远端图像的异步下载和缓存功能整合到UIImageView
 */
@interface UIImageView (WebCache)

#pragma mark - Image State

/**
 * 获取当前的图片的URL
 */
@property (nonatomic, strong, readonly, nullable) NSURL *sd_currentImageURL;

#pragma mark - 图片加载（9个方法）

/**
 * 通过`url`设置图片
 *
 * 异步下载并且会缓存下载的图片
 *
 * @param url 远端图片的url地址
 * @discussion  NS_REFINED_FOR_SWIFT 宏的作用是Swift 中隐藏 该Objective-C类型的 API
 */
- (void)sd_setImageWithURL:(nullable NSURL *)url NS_REFINED_FOR_SWIFT;

/**
 * 通过`url`设置图片和占位图
 *
 * 异步下载并且会缓存下载的图片
 *
 * @param url         远端图片的url地址
 * @param placeholder 最初显示的图片, 直到远端图片被请求回来
 * @see sd_setImageWithURL:placeholderImage:options:
 */
- (void)sd_setImageWithURL:(nullable NSURL *)url
          placeholderImage:(nullable UIImage *)placeholder NS_REFINED_FOR_SWIFT;

/**
 * 通过`url`设置图片和占位图以及自定义选项
 *
 * 异步下载并且会缓存下载的图片
 *
 * @param url         远端图片的url地址
 * @param placeholder 最初显示的图片, 直到远端图片被请求回来
 * @param options     这些选项会在下载图片的过程中被使用.
 * @see `SDWebImageOptions` 包含了可用的选项
 */
- (void)sd_setImageWithURL:(nullable NSURL *)url
          placeholderImage:(nullable UIImage *)placeholder
                   options:(SDWebImageOptions)options NS_REFINED_FOR_SWIFT;

/**
 * 通过`url`设置图片和占位图以及自定义选项及上下文
 *
 * 异步下载并且会缓存下载的图片
 *
 * @param url         远端图片的url地址
 * @param placeholder 最初显示的图片, 直到远端图片被请求回来
 * @param options     这些选项会在下载图片的过程中被使用.
 * @see `SDWebImageOptions` 包含了可用的选项
 * @param context     包含了不同操作选项的上下文, `SDWebImageContextOption`包含了`SDWebImageOptions`无法支持的额外操作.
 */
- (void)sd_setImageWithURL:(nullable NSURL *)url
          placeholderImage:(nullable UIImage *)placeholder
                   options:(SDWebImageOptions)options
                   context:(nullable SDWebImageContext *)context;

/**
 * 通过`url`设置图片
 *
 * 异步下载并且会缓存下载的图片
 *
 * @param url            远端图片的url地址
 * @param completedBlock 当图片加载完成会调用这个block，这是一个无返回值有四个参数的block
 *                          第一个参数：通过url下载的图片
 *                          第二个参数：下载出错的error
 *                          第三个参数：标识图片的来源（网络下载还是缓存数据）
 *                          第四个参数：下载图片的url地址
 */
- (void)sd_setImageWithURL:(nullable NSURL *)url
                 completed:(nullable SDExternalCompletionBlock)completedBlock;

/**
 * 通过`url`设置图片和占位图
 *
 * 异步下载并且会缓存下载的图片
 *
 * @param url            远端图片的url地址
 * @param placeholder    最初显示的图片, 直到远端图片被请求回来
 * @param completedBlock 当图片加载完成会调用这个block，这是一个无返回值有四个参数的block
 *                          第一个参数：通过url下载的图片
 *                          第二个参数：下载出错的error
 *                          第三个参数：标识图片的来源（网络下载还是缓存数据）
 *                          第四个参数：下载图片的url地址
 */
- (void)sd_setImageWithURL:(nullable NSURL *)url
          placeholderImage:(nullable UIImage *)placeholder
                 completed:(nullable SDExternalCompletionBlock)completedBlock NS_REFINED_FOR_SWIFT;

/**
 * 通过`url`设置图片和占位图以及自定义选项
 *
 * 异步下载并且会缓存下载的图片
 *
 * @param url            远端图片的url地址
 * @param placeholder    最初显示的图片, 直到远端图片被请求回来
 * @param options        这些选项会在下载图片的过程中被使用.
 * @see `SDWebImageOptions` 包含了可用的选项
 * @param completedBlock 当图片加载完成会调用这个block，这是一个无返回值有四个参数的block
 *                          第一个参数：通过url下载的图片
 *                          第二个参数：下载出错的error
 *                          第三个参数：标识图片的来源（网络下载还是缓存数据）
 *                          第四个参数：下载图片的url地址
 */
- (void)sd_setImageWithURL:(nullable NSURL *)url
          placeholderImage:(nullable UIImage *)placeholder
                   options:(SDWebImageOptions)options
                 completed:(nullable SDExternalCompletionBlock)completedBlock;

/**
 * 通过`url`设置图片和占位图以及自定义选项
 *
 * 异步下载并且会缓存下载的图片
 *
 * @param url            远端图片的url地址
 * @param placeholder    最初显示的图片, 直到远端图片被请求回来
 * @param options        这些选项会在下载图片的过程中被使用.
 * @see `SDWebImageOptions` 包含了可用的选项
 * @param progressBlock  图片下载过程中会调用这个block
 *                       @note 这个block执行在后台队列
 * @param completedBlock 当图片加载完成会调用这个block，这是一个无返回值有四个参数的block
 *                          第一个参数：通过url下载的图片
 *                          第二个参数：下载出错的error
 *                          第三个参数：标识图片的来源（网络下载还是缓存数据）
 *                          第四个参数：下载图片的url地址
 */
- (void)sd_setImageWithURL:(nullable NSURL *)url
          placeholderImage:(nullable UIImage *)placeholder
                   options:(SDWebImageOptions)options
                  progress:(nullable SDImageLoaderProgressBlock)progressBlock
                 completed:(nullable SDExternalCompletionBlock)completedBlock;

/**
 * 通过`url`设置图片和占位图以及自定义选项及上下文
 *
 * 异步下载并且会缓存下载的图片
 *
 * @param url            远端图片的url地址
 * @param placeholder    最初显示的图片, 直到远端图片被请求回来
 * @param options        这些选项会在下载图片的过程中被使用.
 * @see `SDWebImageOptions` 包含了可用的选项
 * @param context        包含了不同操作选项的上下文, `SDWebImageContextOption`包含了`SDWebImageOptions`无法支持的额外操作.
 * @param progressBlock  图片下载过程中会调用这个block
 *                       @note 这个block执行在后台队列
 * @param completedBlock 当图片加载完成会调用这个block，这是一个无返回值有四个参数的block
 *                          第一个参数：通过url下载的图片
 *                          第二个参数：下载出错的error
 *                          第三个参数：标识图片的来源（网络下载还是缓存数据）
 *                          第四个参数：下载图片的url地址
 */
- (void)sd_setImageWithURL:(nullable NSURL *)url
          placeholderImage:(nullable UIImage *)placeholder
                   options:(SDWebImageOptions)options
                   context:(nullable SDWebImageContext *)context
                  progress:(nullable SDImageLoaderProgressBlock)progressBlock
                 completed:(nullable SDExternalCompletionBlock)completedBlock;

/**
 * Cancel the current normal image load (for `UIImageView.image`)
 * @note For highlighted image, use `sd_cancelCurrentHighlightedImageLoad`
 */
- (void)sd_cancelCurrentImageLoad;

@end
