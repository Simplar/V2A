//
//  UIImage+OpenCV.h
//

#import <UIKit/UIKit.h>
#import <opencv2/imgcodecs/ios.h>

@interface UIImage (OpenCV)

+ (UIImage *)UIImageFromCVMat:(cv::Mat)cvMat;
- (cv::Mat)cvMatFromUIImage;
+ (UIImage*)drawFront:(UIImage*)image text:(NSString*)text atPoint:(CGPoint)point;

@end
