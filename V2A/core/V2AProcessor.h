#ifndef V2AProcessor_h
#define V2AProcessor_h

#include "V2AError.h"
#include "V2ASoundGenerator.h"

#import <opencv2/opencv.hpp>

class V2AProcessor
{
public:
    V2AProcessor();
    virtual ~V2AProcessor();
    
    Error initProcessor();
    
    Error newFrame(const cv::Mat & rgba);
    
    cv::Rect getCurrentROI();
    
private:
    V2ASoundGenerator sound_gen;
    cv::Mat gray;
    
    float ROI_WidthRate, ROI_ShiftRate;
    cv::Rect roi;
    
    Error shiftROI();
};


#endif /* V2AProcessor_h */
