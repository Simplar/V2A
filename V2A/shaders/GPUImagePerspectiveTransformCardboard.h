#ifndef GPUImagePerspectiveTransformCardboard_h
#define GPUImagePerspectiveTransformCardboard_h

#import <GPUImage/GPUImage.h>

@interface GPUImagePerspectiveTransformCardboard: GPUImageFilter
{
    GLfloat shiftXUniform, shiftYUniform, newSizeUniform;
}

- (id)init;

@end


#endif /* GPUImagePerspectiveTransformCardboard_h */
