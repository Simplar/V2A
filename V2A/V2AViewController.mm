#import "V2AViewController.h"

// GPUImage
#include "GPUImageFilter.h"
#include "GPUImageVideoCamera.h"
#include "GPUImageVideoCameraRGB.h"
#include "GPUImageGrayscaleFilter.h"
#include "GPUImageRawDataOutput.h"
#include "GPUImageView.h"
#include "GPUImageGraphicsFilter.h"
#include "GPUImagePerspectiveTransformCardboard.h"

// AVFoundation
#import <AVFoundation/AVAudioSession.h>

// OpenCV
#import "UIImage+OpenCV.h"
#import <opencv2/opencv.hpp>
#import <opencv2/videoio/cap_ios.h>
#include "opencv2/imgproc/imgproc.hpp"

// Core
#include "V2AError.h"
#include "V2AiOS_staff.h"
#include "V2AProcessor.h"

bool GlobalDebugMode = getBoolParam(@"GlobalDebugMode");

using namespace std;

bool DebugPtsDrawing = true;

@interface V2AViewController ()
{
    V2AProcessor proc;
    cv::Mat rgba;
}

/// GPUImage filters

// Camera and resulting images
@property (nonatomic, strong) GPUImageVideoCamera *videoCamera;
@property (nonatomic, strong) GPUImageView *gpuImageView;
@property (nonatomic, strong) GPUImageFilter *extractYFilter;
@property (nonatomic, strong) GPUImageFilter *extractRGBFilter;
@property (nonatomic, strong) GPUImagePerspectiveTransformCardboard *perspectiveTransformCardboard;
@property (atomic) CGSize screenSize;
@property (atomic) CGSize cameraSize;

// Preprocessing
@property (nonatomic, strong) GPUImageGrayscaleFilter *grayscaleFilter;

// Intermidiate raw data
@property (nonatomic, strong) GPUImageRawDataOutput *edgesRawData;

// Postprocessing
@property (nonatomic, strong) GPUImageGraphicsFilter *graphicsFilter;
@property (nonatomic, strong) GPUImageAlphaBlendFilter *blendFilterGraphics;

// Debugging
@property (atomic) double ticks;

@end

@implementation V2AViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.ticks = -1;
    
    [self startVideoCamera];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
    
- (void)dealloc {
    NSLog(@"V2AViewController was deallocated");
}
    
#pragma mark - CV / Private
    
- (void)configureProcessor {
    Error err;
    err = proc.initProcessor();
    CV_Assert( err == ErrorOk );
}
    
    
- (void)configureGPUImageFilters {
    // Init filters
    _extractRGBFilter = [[GPUImageFilter alloc] initWithFragmentShaderFromFile:@"ExtractRGB"];
    _extractYFilter =   [[GPUImageFilter alloc] initWithFragmentShaderFromFile:@"ExtractY"];
    _grayscaleFilter = [[GPUImageGrayscaleFilter alloc] init];
    _perspectiveTransformCardboard = [[GPUImagePerspectiveTransformCardboard alloc] init];
    
    // Intermidiate raw data
    _edgesRawData = [[GPUImageRawDataOutput alloc] initWithImageSize:_cameraSize resultsInBGRAFormat:NO];
    
    // Postprocessing
    _graphicsFilter = [[GPUImageGraphicsFilter alloc] initWithInputFrameSize:_cameraSize outputFrameSize:_screenSize];
    _blendFilterGraphics = [[GPUImageAlphaBlendFilter alloc] init];
    _blendFilterGraphics.mix = 1.f;
    
    // Camera
    GPUImageOutput *grayOutput = _grayscaleFilter;;
    GPUImageOutput *rgbOutput = _videoCamera;
    [_videoCamera addTarget: _grayscaleFilter];
    
    // RGB
    [rgbOutput addTarget: _edgesRawData];
    
    // Graphics
    [rgbOutput addTarget: _blendFilterGraphics];
    [_graphicsFilter addTarget: _blendFilterGraphics];
    
    // VR
    [_blendFilterGraphics addTarget: _perspectiveTransformCardboard];
    
    GPUImageOutput *to_view;
    int to_view_par = getIntParam(@"ToView");
    switch( to_view_par )
    {
        case 0: to_view = _blendFilterGraphics; break;
        case 1: to_view = _perspectiveTransformCardboard; break;
        case 2: to_view = rgbOutput; break;
        case 3: to_view = rgbOutput; break;
        case 4: to_view = rgbOutput; break;
    }
    [to_view addTarget: self.gpuImageView]; // _blendFilterHints _thresholdFilter
    
    // Setting filter sizes
    CGSize _cameraSizeD2 = CGSizeMake(int(_cameraSize.width/2), int(_cameraSize.height/2) );
    CGSize _cameraSizeD4 = CGSizeMake(int(_cameraSize.width/4), int(_cameraSize.height/4) );
    [_grayscaleFilter               forceProcessingAtSizeRespectingAspectRatio:_cameraSize];
    [_extractRGBFilter              forceProcessingAtSizeRespectingAspectRatio:_cameraSize];
    [_extractYFilter                forceProcessingAtSizeRespectingAspectRatio:_cameraSize];
    [_graphicsFilter                setInputSize:_cameraSize atIndex:0];
    [_blendFilterGraphics           forceProcessingAtSizeRespectingAspectRatio:_cameraSize];
    [_perspectiveTransformCardboard forceProcessingAtSizeRespectingAspectRatio:_cameraSize];
}

- (void)processOnCPU {
    GPUImageRawDataOutput *weakRawData = _edgesRawData;
    [weakRawData lockFramebufferForReading];
    
    GLubyte *outputBytes = [weakRawData rawBytesForImage];
    NSInteger bytesPerRow = [weakRawData bytesPerRowInOutput];
    
    // get cv::Mat from bytes
    rgba = cv::Mat(self.cameraSize.height, int(bytesPerRow/4), CV_8UC4, (void*)outputBytes);
    if (rgba.cols != self.cameraSize.width) {
        rgba = (rgba.colRange(0, self.cameraSize.width));
    }
    
    /* Write frame to album
    UIImage * uiimage = [UIImage UIImageFromCVMat:rgba];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        UIImageWriteToSavedPhotosAlbum(uiimage, nil, nil, nil);
    });
    //*/
    
    Error err;
    
    err = proc.newFrame(rgba);
    CV_Assert( err == ErrorOk );
    
    // Graphics
    self.graphicsFilter.shouldDrawROI = YES;
    cv::Rect roi = proc.getCurrentROI();
    [self.graphicsFilter setROI: roi];
    [self.graphicsFilter render];
    
    // debug drawing
    if (DebugPtsDrawing) {
        vector<cv::Point2f> debug_pts;
        vector<cv::Rect> debug_rois;
        [self.graphicsFilter setDebugData:debug_pts: debug_rois];
    }
    
    /* check fps
     double fps = cv::getTickFrequency()/(cv::getTickCount() - weakSelf.ticks);
     weakSelf.ticks = cv::getTickCount();
     printf("fps: %2.1f\n", fps);
     //*/
    
    [weakRawData unlockFramebufferAfterReading];
}

- (void)configureCameraAndUI
{
    // autorotation bug patch
    NSNumber *value = [NSNumber numberWithInt:UIInterfaceOrientationPortrait];
    [[UIDevice currentDevice] setValue:value forKey:@"orientation"];
    
    // AVCaptureSessionPreset640x480 / AVCaptureSessionPreset1280x720 / AVCaptureSessionPreset1920x1080
    NSString * sessionPreset = AVCaptureSessionPreset1280x720;
    
    self.videoCamera = [[GPUImageVideoCamera alloc] initWithSessionPreset:sessionPreset cameraPosition:AVCaptureDevicePositionBack];
    self.videoCamera.runBenchmark = NO;
    self.videoCamera.outputImageOrientation = UIInterfaceOrientationLandscapeRight;
    self.videoCamera.delegate = (id)self;
    self.videoCamera.frameRate = 30;
    
    if ([self.videoCamera.videoCaptureConnection isVideoStabilizationSupported]) {
        self.videoCamera.videoCaptureConnection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeStandard;
    }
    
    if ([self.videoCamera.inputCamera lockForConfiguration: nil]) {
        if (self.videoCamera.inputCamera.isSmoothAutoFocusSupported) {
            self.videoCamera.inputCamera.smoothAutoFocusEnabled = YES;
        }
        [self.videoCamera.inputCamera unlockForConfiguration];
    }
    
    CGRect mainScreenFrame = [[UIScreen mainScreen] bounds];
    UIView *primaryView = [[UIView alloc] initWithFrame:mainScreenFrame];
    primaryView.backgroundColor = [UIColor blueColor];
    self.view = primaryView;
    self.gpuImageView = [[GPUImageView alloc] initWithFrame:CGRectMake(0.0, 0.0, mainScreenFrame.size.width, mainScreenFrame.size.height)];
    [primaryView addSubview:self.gpuImageView];
}

- (void)configureAudio
{
    AVAudioSession *session = [AVAudioSession sharedInstance];
    
    NSError *err = nil;
    if (![session setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&err])
    {
        NSLog(@"Cannot init audiosession");
        CV_Assert( false );
    }
    
    if (![session setActive:YES error:&err])
    {
        NSLog(@"Cannot activate audiosession");
        CV_Assert( false );
    }
}
    
- (void)configureGPUCPU {
    
    // GPU Filters
    [self configureGPUImageFilters];
    
    /// CPU processing block
    __weak typeof(self) weakSelf = self;
    [_edgesRawData setNewFrameAvailableBlock:^{
        [weakSelf processOnCPU];
    }];
}
    
#pragma mark - Camera Controll
    
- (void)startVideoCamera {
    self.cameraSize = CGSizeMake(720, 1280); //AVCaptureSessionPreset1280x720
    
    [self configureCameraAndUI];
    self.screenSize = self.gpuImageView.frame.size;
    
    [self configureAudio];
    [self configureProcessor];
    [self configureGPUCPU];
    
    self.gpuImageView.hidden = NO;
    
    [self.videoCamera startCameraCapture];
}
    
- (void)stopVideoCamera {
        [self.videoCamera stopCameraCapture];
}

- (void)willOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    // every frame work
    
    if (getIntParam(@"AdjustParams"))
    {
        double mi = getDoubleParam(@"Mi");
        double ma = getDoubleParam(@"Ma");
        double step = (ma-mi)/400;
        static double param = mi;
        param += step;
        if(param > ma)
            param = mi;
        cout << "Param: " << param << endl;
        
        //_gradientBlurFilter.threshold = param;
    }
}
    
@end

