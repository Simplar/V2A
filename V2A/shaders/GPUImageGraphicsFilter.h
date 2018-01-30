#ifndef GPUImageGraphicsFilter_h
#define GPUImageGraphicsFilter_h

#import <GPUImage/GPUImage.h>
#import <opencv2/opencv.hpp>

@interface GPUImageGraphicsFilter: GPUImageFilter
{
    GLint colorUniform;
    std::vector<GLfloat> roiVertexes;
    CFAbsoluteTime startShowingGpaphicsTime, OneGraphicsDrawingTime, WaitGraphicsTime;
    
    std::vector< std::vector<GLfloat> > debugPts, debugROIs;
}

- (id)initWithInputFrameSize:(CGSize)inputFrameSize outputFrameSize:(CGSize)outputFrameSize;

- (void)render;

-(void)setROI:(const cv::Rect &) roi;

-(void)setDebugData:(const std::vector<cv::Point2f> &)pts :(const std::vector<cv::Rect> &)ROIs;

@property(readwrite, atomic) BOOL shouldDrawROI;
@property(readonly, atomic) CGSize inputFrameSizeHints;
@property(readonly, atomic) CGSize outputFrameSizeHints;

@end


#endif /* GPUImageGraphicsFilter_h */
