#import <Foundation/Foundation.h>

#include "GPUImageGraphicsFilter.h"

#include <string>

using namespace std;


NSString *const kGPUImageGraphicsFragmentShaderString = SHADER_STRING
(
 uniform highp vec4 colorUniform;
 
 void main()
 {
     gl_FragColor = vec4(colorUniform);
 }
 );

NSString *const kGPUImageGraphicsVertexShaderString = SHADER_STRING
(
 attribute vec4 position;
 
 void main()
 {
     gl_Position = position;
 }
 );


@implementation GPUImageGraphicsFilter

- (id)initWithInputFrameSize:(CGSize)inputFrameSize outputFrameSize:(CGSize)outputFrameSize {
    if (!(self = [super initWithVertexShaderFromString:kGPUImageGraphicsVertexShaderString
                              fragmentShaderFromString:kGPUImageGraphicsFragmentShaderString]))
    {
        return nil;
    }
    
    if(inputFrameSize.width==0 || inputFrameSize.height==0 ||
       outputFrameSize.width==0 || outputFrameSize.height==0 )
    {
        cerr << "Error: Bad size in initWithInputFrameSize..." << endl;
        return nil;
    }
    
    _inputFrameSizeHints = inputFrameSize;
    _outputFrameSizeHints = outputFrameSize;
    
    colorUniform = [filterProgram uniformIndex:@"colorUniform"];
    
    
    self->startShowingGpaphicsTime = 0.;
    self->OneGraphicsDrawingTime = 1.25;
    self->WaitGraphicsTime = 3.;
    
    return self;
}

- (void)renderToTextureWithVertices:(const GLfloat *)vertices textureCoordinates:(const GLfloat *)textureCoordinates;
{
    // Prevent rendering of the frame by normal means
}

- (void)render
{
    if (self.preventRendering)
    {
        return;
    }
    
    [GPUImageContext setActiveShaderProgram:filterProgram];
    outputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:[self sizeOfFBO] textureOptions:self.outputTextureOptions onlyTexture:NO];
    [outputFramebuffer activateFramebuffer];
    
    glClearColor(0.0, 0.0, 0.0, 0.0);
    glClear(GL_COLOR_BUFFER_BIT);
    
    const int dim = 2; // space dimension: (x,y)
    
    if(_shouldDrawROI && !roiVertexes.empty())
    {
        glLineWidth(5.);
        [self setVec4:GPUVector4({0.0,0.0,1.0,1.0}) forUniform:colorUniform program:filterProgram];
        GLsizei count = GLsizei(roiVertexes.size()/dim);
        GLfloat * data = roiVertexes.data();
        
        glVertexAttribPointer(filterPositionAttribute, dim, GL_FLOAT, 0, 0, data );
        glDrawArrays(GL_LINE_LOOP, 0, count);
        glLineWidth(1.f);
    }
    
    /// debug drawing
    if( !debugPts.empty() )
    {
        [self setVec4:GPUVector4({1.0, 0.0 ,0.0, 1.0}) forUniform:colorUniform program:filterProgram];
        
        for(std::vector<GLfloat> & vertexes: debugPts)
        {
            GLsizei count = GLsizei(vertexes.size()/dim);
            GLfloat * data = vertexes.data();
            
            glVertexAttribPointer(filterPositionAttribute, dim, GL_FLOAT, 0, 0, data );
            glDrawArrays(GL_TRIANGLE_FAN, 0, count);
        }
    }
    
    if( !debugROIs.empty() )
    {
        glLineWidth(1.);
        [self setVec4:GPUVector4({1.0,0.0,0.0,1.0}) forUniform:colorUniform program:filterProgram];
        
        for(std::vector<GLfloat> roi: debugROIs)
        {
            GLsizei count = GLsizei(roi.size()/dim);
            GLfloat * data = roi.data();
            
            glVertexAttribPointer(filterPositionAttribute, dim, GL_FLOAT, 0, 0, data );
            glDrawArrays(GL_LINE_LOOP, 0, count);
        }
        glLineWidth(1.f);
    }
    
    [self informTargetsAboutNewFrameAtTime: kCMTimeInvalid];
}

-(void)setROI:(const cv::Rect &)roi
{
    roiVertexes.clear();
    vector<cv::Point2f> roi_pts = {cv::Point2f(roi.x, roi.y),
                                   cv::Point2f(roi.x+roi.width, roi.y),
                                   cv::Point2f(roi.x+roi.width, roi.y+roi.height),
                                   cv::Point2f(roi.x, roi.y+roi.height)};
    
    for(const cv::Point2f & pt: roi_pts)
    {
        roiVertexes.push_back( GLfloat(pt.x)/_inputFrameSizeHints.width  *2-1);
        roiVertexes.push_back( GLfloat(pt.y)/_inputFrameSizeHints.height *2-1);
    }
    
}

-(void)calculateCircleVertexes:(std::vector<GLfloat> &)vertexes WithCenter:(const cv::Point2f &)center AndRadius:(GLfloat)radius
{
    const float resolution = 40.f;
    const float ratio = 1.f * self.inputFrameSizeHints.height / self.inputFrameSizeHints.width;
    float delta_theta = M_PI * 2.0f / resolution;
    
    for (float i = resolution; i >= 0.f; i--)
    {
        float theta = delta_theta * i;
        vertexes.push_back(center.x + cos(theta) * radius * ratio);
        vertexes.push_back(center.y + sin(theta) * radius);
    }
    
}

-(void)setDebugData:(const std::vector<cv::Point2f> &)pts :(const std::vector<cv::Rect> &)ROIs
{
    debugPts.clear();
    debugROIs.clear();
    
    for(const cv::Point2f & pt: pts)
    {
        debugPts.resize(debugPts.size() + 1);
        cv::Point2f center(GLfloat(pt.x)/_inputFrameSizeHints.width  *2-1, GLfloat(pt.y)/_inputFrameSizeHints.height *2-1);
        GLfloat radius_opengl = 0.004;
        
        vector<GLfloat> vertexes;
        [self calculateCircleVertexes: vertexes WithCenter:center AndRadius:radius_opengl];
        debugPts.push_back(vertexes);
    }
    
    for(const cv::Rect & roi: ROIs)
    {
        vector<GLfloat> roi_vert;
        vector<cv::Point2f> pts_roi = {roi.tl(), cv::Point2f(roi.tl())+cv::Point2f(roi.width, 0), roi.br(), cv::Point2f(roi.tl())+cv::Point2f(0, roi.height) };
        for(const cv::Point2f & pt: pts_roi)
        {
            cv::Point2f pt_ogl(GLfloat(pt.x)/_inputFrameSizeHints.width  *2-1, GLfloat(pt.y)/_inputFrameSizeHints.height *2-1);
            roi_vert.push_back(pt_ogl.x);
            roi_vert.push_back(pt_ogl.y);
        }
        
        debugROIs.push_back(roi_vert);
    }
}

@end
