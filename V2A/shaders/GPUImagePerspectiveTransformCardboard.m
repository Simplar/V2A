#include "GPUImagePerspectiveTransformCardboard.h"

NSString *const kGPUImagePerspectiveTransformBlendFragmentShaderString = SHADER_STRING
(
 varying highp vec2 textureCoordinate;
 
 uniform sampler2D inputImageTexture;
 uniform highp float shift_x; // shift from left screen border
 uniform highp float shift_y; // shift from central horizontal line
 uniform highp float new_size;
 
 void main()
 {
     highp vec2 coords;
     highp vec2 center = vec2(new_size, new_size);
     
     if(textureCoordinate.x < 0.5)
     {
         coords = textureCoordinate.xy/new_size + vec2(0.5-0.5/new_size, 0.5-0.5/new_size) + vec2(shift_x, shift_y)/new_size;
     }
     else
     {
         coords = textureCoordinate.xy/new_size + vec2(0.5-0.5/new_size, 0.5-0.5/new_size) + vec2(-shift_x, shift_y)/new_size;
     }
     
     if( coords.x > 0. && coords.y > 0. && coords.x < 1. && coords.y < 1.)
         gl_FragColor = texture2D(inputImageTexture, coords);
     else
         gl_FragColor = vec4(0.,0.,0.,1.);
     
     // central line
     if(textureCoordinate.x > 0.495 && textureCoordinate.x < 0.505)
         gl_FragColor = vec4(1., 1., 1., 1.);
     
     /* debug drawing
      if(textureCoordinate.x-shift_x > 0.49 && textureCoordinate.x-shift_x < 0.51)
      {
      if(textureCoordinate.y < 0.5 && textureCoordinate.y+shift_y > 0.49 && textureCoordinate.y+shift_y < 0.51)
      gl_FragColor = vec4(1., 0., 0., 1.);
      if(textureCoordinate.y > 0.5 && textureCoordinate.y-shift_y > 0.49 && textureCoordinate.y-shift_y < 0.51)
      gl_FragColor = vec4(0., 0., 1., 1.);
      }
      //*/
     
 }
 );

// processing is in fragment shader
NSString *const kGPUImagePerspectiveTransformBlendVertexShaderString = SHADER_STRING
(
 attribute vec4 position;
 attribute vec4 inputTextureCoordinate;
 
 varying vec2 textureCoordinate;
 
 void main()
 {
     textureCoordinate = inputTextureCoordinate.xy;
     gl_Position = position;
 }
 );


@implementation GPUImagePerspectiveTransformCardboard

#pragma mark Initialization
- (id)init {
    if (!(self = [super initWithVertexShaderFromString:kGPUImagePerspectiveTransformBlendVertexShaderString
                              fragmentShaderFromString:kGPUImagePerspectiveTransformBlendFragmentShaderString
                  ] )) // processing is in fragment shader
    {
        return nil;
    }
    
    shiftXUniform = [filterProgram uniformIndex:@"shift_x"];
    shiftYUniform = [filterProgram uniformIndex:@"shift_y"];
    newSizeUniform = [filterProgram uniformIndex:@"new_size"];
    
    [self initTransforms];
    
    return self;
}

- (void)initTransforms
{
    double screen_width, screen_height; // in inches
    int screen_height_px = UIScreen.mainScreen.nativeBounds.size.height;
    double fov_size = 3.6 / 2.54; // field of view for cardboard v1
    
    // use height in pixels to determine physical screen size
    switch(screen_height_px)
    {
        case 1136: // 5, 5S, SE
            screen_width  = (0.5 + 4.99) / 2.54;  // this includes distance to phone border (~5mm)
            screen_height = 8.84 / 2.54;
            break;
        case 1334: // 6, 6S
            screen_width  = (0.45 + 5.84) / 2.54;  // this includes distance to phone border (~4.5mm)
            screen_height = 10.39 / 2.54;
            break;
        case 2208:
        case 1920: // 6+, 7+
            screen_width =  (0.4 + 6.83) / 2.54; // this includes distance to phone border (~4mm)
            screen_height = 12.76 / 2.54;
            break;
        default: // 6, 6S are default screen size
            screen_width  = (0.45 + 5.84) / 2.54;  // this includes distance to phone border (~4.5mm)
            screen_height = 10.39 / 2.54;
            break;
    }
    std::swap(screen_width, screen_height);
    
    // shift
    double shift_x = 1.26 / screen_width; // 33mm ~ 1.30 inch - distance from left phone border
    double shift_y = 1.30 / screen_height - 0.5; // 32mm ~ 1.26 inch - distance from central horizontal line
    
    // scaling
    double new_size = fov_size / screen_height;
    
    [self setFloat: shift_x forUniform: shiftXUniform program: filterProgram];
    [self setFloat: shift_y forUniform: shiftYUniform program: filterProgram];
    [self setFloat: new_size forUniform: newSizeUniform program: filterProgram];
}

@end
