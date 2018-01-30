//
//  CvVideoCameraWrapper.m
//

#import "GPUImageVideoCameraRGB.h"
#import "GPUImageMovieWriter.h"
#import "GPUImageFilter.h"

NSString *const kGPUImageRGBFragmentShaderString = SHADER_STRING
(
 varying highp vec2 textureCoordinate;
 
 uniform sampler2D texture;
 
 void main()
 {
     highp vec4 rgba = texture2D(texture, textureCoordinate).bgra;
     
     gl_FragColor = rgba;
 }
);

#pragma mark -
#pragma mark Private methods and instance variables

@interface GPUImageVideoCameraRGB ()
{
    NSDate *startingCaptureTime;
    
    dispatch_queue_t cameraProcessingQueue, audioProcessingQueue;
    
    GLProgram *program;
    GLint positionAttribute, textureCoordinateAttribute;
    GLint textureUniform;

    int imageBufferWidth, imageBufferHeight;
}
@end

@implementation GPUImageVideoCameraRGB

@synthesize captureSessionPreset = _captureSessionPreset;
@synthesize runBenchmark = _runBenchmark;
@synthesize outputImageOrientation = _outputImageOrientation;
@synthesize horizontallyMirrorFrontFacingCamera = _horizontallyMirrorFrontFacingCamera, horizontallyMirrorRearFacingCamera = _horizontallyMirrorRearFacingCamera;
@synthesize frameRate = _frameRate;

#pragma mark -
#pragma mark Initialization and teardown

- (id)initWithSessionPreset:(NSString *)sessionPreset cameraPosition:(AVCaptureDevicePosition)cameraPosition;
{
    if (!(self = [super initWithSessionPreset:sessionPreset cameraPosition:cameraPosition]))
    {
        return nil;
    }
    
    captureAsYUV = NO;
    
    runSynchronouslyOnVideoProcessingQueue(^{
        
        [GPUImageContext useImageProcessingContext];
        program = [[GPUImageContext sharedImageProcessingContext]
                                programForVertexShaderString:kGPUImageVertexShaderString
                                        fragmentShaderString:kGPUImageRGBFragmentShaderString];
        if (!program.initialized)
        {
            [program addAttribute:@"position"];
            [program addAttribute:@"inputTextureCoordinate"];
            
            if (![program link])
            {
                NSString *progLog = [program programLog];
                NSLog(@"Program link log: %@", progLog);
                NSString *fragLog = [program fragmentShaderLog];
                NSLog(@"Fragment shader compile log: %@", fragLog);
                NSString *vertLog = [program vertexShaderLog];
                NSLog(@"Vertex shader compile log: %@", vertLog);
                program = nil;
                NSAssert(NO, @"Filter shader link failed");
            }
        }
        
        positionAttribute = [program attributeIndex:@"position"];
        textureCoordinateAttribute = [program attributeIndex:@"inputTextureCoordinate"];
        textureUniform = [program uniformIndex:@"texture"];
        
        [GPUImageContext setActiveShaderProgram:program];
        
        glEnableVertexAttribArray(positionAttribute);
        glEnableVertexAttribArray(textureCoordinateAttribute);
    });
    
    return self;
}

- (GPUImageFramebuffer *)framebufferForOutput;
{
    return outputFramebuffer;
}

#define INITIALFRAMESTOIGNOREFORBENCHMARK 5

- (void)updateTargetsForVideoCameraUsingCacheTextureAtWidth:(int)bufferWidth height:(int)bufferHeight time:(CMTime)currentTime;
{
    // First, update all the framebuffers in the targets
    for (id<GPUImageInput> currentTarget in targets)
    {
        if ([currentTarget enabled])
        {
            NSInteger indexOfObject = [targets indexOfObject:currentTarget];
            NSInteger textureIndexOfTarget = [[targetTextureIndices objectAtIndex:indexOfObject] integerValue];
            
            if (currentTarget != self.targetToIgnoreForUpdates)
            {
                [currentTarget setInputRotation:outputRotation atIndex:textureIndexOfTarget];
                [currentTarget setInputSize:CGSizeMake(bufferWidth, bufferHeight) atIndex:textureIndexOfTarget];
                
                if ([currentTarget wantsMonochromeInput] && captureAsYUV)
                {
                    [currentTarget setCurrentlyReceivingMonochromeInput:YES];
                    // TODO: Replace optimization for monochrome output
                    [currentTarget setInputFramebuffer:outputFramebuffer atIndex:textureIndexOfTarget];
                }
                else
                {
                    [currentTarget setCurrentlyReceivingMonochromeInput:NO];
                    [currentTarget setInputFramebuffer:outputFramebuffer atIndex:textureIndexOfTarget];
                }
            }
            else
            {
                [currentTarget setInputRotation:outputRotation atIndex:textureIndexOfTarget];
                [currentTarget setInputFramebuffer:outputFramebuffer atIndex:textureIndexOfTarget];
            }
        }
    }
    
    // Then release our hold on the local framebuffer to send it back to the cache as soon as it's no longer needed
    [outputFramebuffer unlock];
    outputFramebuffer = nil;
    
    // Finally, trigger rendering as needed
    for (id<GPUImageInput> currentTarget in targets)
    {
        if ([currentTarget enabled])
        {
            NSInteger indexOfObject = [targets indexOfObject:currentTarget];
            NSInteger textureIndexOfTarget = [[targetTextureIndices objectAtIndex:indexOfObject] integerValue];
            
            if (currentTarget != self.targetToIgnoreForUpdates)
            {
                [currentTarget newFrameReadyAtTime:currentTime atIndex:textureIndexOfTarget];
            }
        }
    }
}

- (void)processVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer;
{
    if (capturePaused)
    {
        return;
    }
    
    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    CVImageBufferRef cameraFrame = CMSampleBufferGetImageBuffer(sampleBuffer);
    int bufferWidth = (int) CVPixelBufferGetWidth(cameraFrame);
    int bufferHeight = (int) CVPixelBufferGetHeight(cameraFrame);
    
    CMTime currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    
    [GPUImageContext useImageProcessingContext];
    
    CVPixelBufferLockBaseAddress(cameraFrame, 0);
    
    CVOpenGLESTextureRef textureRef = NULL;
    
    CVPixelBufferLockBaseAddress(cameraFrame, 0);
    
    if ( (imageBufferWidth != bufferWidth) && (imageBufferHeight != bufferHeight) )
    {
        imageBufferWidth = bufferWidth;
        imageBufferHeight = bufferHeight;
    }
    
    CVReturn err;
    // Y-plane
    glActiveTexture(GL_TEXTURE4);
    err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, [[GPUImageContext sharedImageProcessingContext] coreVideoTextureCache], cameraFrame, NULL, GL_TEXTURE_2D, GL_RGBA, bufferWidth, bufferHeight, GL_RGBA, GL_UNSIGNED_BYTE, 0, &textureRef);
    if (err)
    {
        NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
    }
    
    texture = CVOpenGLESTextureGetName(textureRef);
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    [self obtainFrameRGBA];
    
    int rotatedImageBufferWidth = bufferWidth, rotatedImageBufferHeight = bufferHeight;
    
    if (GPUImageRotationSwapsWidthAndHeight(internalRotation))
    {
        rotatedImageBufferWidth = bufferHeight;
        rotatedImageBufferHeight = bufferWidth;
    }
    
    [self updateTargetsForVideoCameraUsingCacheTextureAtWidth:rotatedImageBufferWidth height:rotatedImageBufferHeight time:currentTime];
    
    CVPixelBufferUnlockBaseAddress(cameraFrame, 0);
    CFRelease(textureRef);
        
        
        
    
    CVPixelBufferUnlockBaseAddress(cameraFrame, 0);
    
    if (_runBenchmark)
    {
        numberOfFramesCaptured++;
        if (numberOfFramesCaptured > INITIALFRAMESTOIGNOREFORBENCHMARK)
        {
            CFAbsoluteTime currentFrameTime = (CFAbsoluteTimeGetCurrent() - startTime);
            totalFrameTimeDuringCapture += currentFrameTime;
        }
    }
}

- (void)obtainFrameRGBA;
{
    [GPUImageContext setActiveShaderProgram:program];
    
    int rotatedImageBufferWidth = imageBufferWidth, rotatedImageBufferHeight = imageBufferHeight;
    
    if (GPUImageRotationSwapsWidthAndHeight(internalRotation))
    {
        rotatedImageBufferWidth = imageBufferHeight;
        rotatedImageBufferHeight = imageBufferWidth;
    }
    
    outputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:CGSizeMake(rotatedImageBufferWidth, rotatedImageBufferHeight) textureOptions:self.outputTextureOptions onlyTexture:NO];
    [outputFramebuffer activateFramebuffer];
    
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    static const GLfloat squareVertices[] = {
        -1.0f, -1.0f,
        1.0f, -1.0f,
        -1.0f,  1.0f,
        1.0f,  1.0f,
    };
    
    glActiveTexture(GL_TEXTURE4);
    glBindTexture(GL_TEXTURE_2D, texture);
    glUniform1i(textureUniform, 4);
    
    glVertexAttribPointer(positionAttribute, 2, GL_FLOAT, 0, 0, squareVertices);
    glVertexAttribPointer(textureCoordinateAttribute, 2, GL_FLOAT, 0, 0, [GPUImageFilter textureCoordinatesForRotation:internalRotation]);
    
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
}

- (void)updateOrientationSendToTargets;
{
    runSynchronouslyOnVideoProcessingQueue(^{
        
        //    From the iOS 5.0 release notes:
        //    In previous iOS versions, the front-facing camera would always deliver buffers in AVCaptureVideoOrientationLandscapeLeft and the back-facing camera would always deliver buffers in AVCaptureVideoOrientationLandscapeRight.
        
        outputRotation = kGPUImageNoRotation;
        if ([self cameraPosition] == AVCaptureDevicePositionBack)
        {
            if (_horizontallyMirrorRearFacingCamera)
            {
                switch(_outputImageOrientation)
                {
                    case UIInterfaceOrientationPortrait:internalRotation = kGPUImageRotateRightFlipVertical; break;
                    case UIInterfaceOrientationPortraitUpsideDown:internalRotation = kGPUImageRotate180; break;
                    case UIInterfaceOrientationLandscapeLeft:internalRotation = kGPUImageFlipHorizonal; break;
                    case UIInterfaceOrientationLandscapeRight:internalRotation = kGPUImageFlipVertical; break;
                    default:internalRotation = kGPUImageNoRotation;
                }
            }
            else
            {
                switch(_outputImageOrientation)
                {
                    case UIInterfaceOrientationPortrait:internalRotation = kGPUImageRotateRight; break;
                    case UIInterfaceOrientationPortraitUpsideDown:internalRotation = kGPUImageRotateLeft; break;
                    case UIInterfaceOrientationLandscapeLeft:internalRotation = kGPUImageRotate180; break;
                    case UIInterfaceOrientationLandscapeRight:internalRotation = kGPUImageNoRotation; break;
                    default:internalRotation = kGPUImageNoRotation;
                }
            }
        }
        else
        {
            if (_horizontallyMirrorFrontFacingCamera)
            {
                switch(_outputImageOrientation)
                {
                    case UIInterfaceOrientationPortrait:internalRotation = kGPUImageRotateRightFlipVertical; break;
                    case UIInterfaceOrientationPortraitUpsideDown:internalRotation = kGPUImageRotateRightFlipHorizontal; break;
                    case UIInterfaceOrientationLandscapeLeft:internalRotation = kGPUImageFlipHorizonal; break;
                    case UIInterfaceOrientationLandscapeRight:internalRotation = kGPUImageFlipVertical; break;
                    default:internalRotation = kGPUImageNoRotation;
                }
            }
            else
            {
                switch(_outputImageOrientation)
                {
                    case UIInterfaceOrientationPortrait:internalRotation = kGPUImageRotateRight; break;
                    case UIInterfaceOrientationPortraitUpsideDown:internalRotation = kGPUImageRotateLeft; break;
                    case UIInterfaceOrientationLandscapeLeft:internalRotation = kGPUImageNoRotation; break;
                    case UIInterfaceOrientationLandscapeRight:internalRotation = kGPUImageRotate180; break;
                    default:internalRotation = kGPUImageNoRotation;
                }
            }
        }
            
        for (id<GPUImageInput> currentTarget in targets)
        {
            NSInteger indexOfObject = [targets indexOfObject:currentTarget];
            [currentTarget setInputRotation:outputRotation atIndex:[[targetTextureIndices objectAtIndex:indexOfObject] integerValue]];
        }
    });
}

- (void)setOutputImageOrientation:(UIInterfaceOrientation)newValue;
{
    _outputImageOrientation = newValue;
    [self updateOrientationSendToTargets];
}

- (void)setHorizontallyMirrorFrontFacingCamera:(BOOL)newValue
{
    _horizontallyMirrorFrontFacingCamera = newValue;
    [self updateOrientationSendToTargets];
}

- (void)setHorizontallyMirrorRearFacingCamera:(BOOL)newValue
{
    _horizontallyMirrorRearFacingCamera = newValue;
    [self updateOrientationSendToTargets];
}


@end
