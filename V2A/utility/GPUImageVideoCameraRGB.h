//
//  GPUImageVideoCameraRGB.h
//

#ifndef GPUImageVideoCameraRGB_h
#define GPUImageVideoCameraRGB_h

#import "GPUImageVideoCamera.h"


/**
 A GPUImageOutput that provides frames from either camera
 */
@interface GPUImageVideoCameraRGB : GPUImageVideoCamera
{
    GLuint texture;
}

/// @name Initialization and teardown

/** Begin a capture session
 
 See AVCaptureSession for acceptable values
 
 @param sessionPreset Session preset to use
 @param cameraPosition Camera to capture from
 */
- (id)initWithSessionPreset:(NSString *)sessionPreset cameraPosition:(AVCaptureDevicePosition)cameraPosition;

@end

#endif /* GPUImageVideoCameraRGB_h */
