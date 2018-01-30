#include "V2AProcessor.h"

using namespace std;

V2AProcessor::V2AProcessor()
{
    ROI_WidthRate = 0.05;
    ROI_ShiftRate = 0.05;
}

V2AProcessor::~V2AProcessor()
{
    
}

Error V2AProcessor::initProcessor()
{
    return ErrorOk;
}

Error V2AProcessor::shiftROI()
{
    if (gray.empty())
        DEFINE_check_error(ErrorEmptyMat);
    
    //if (roi.x > gray.cols/2) return ErrorOk; //!!!
    
    roi.x += gray.cols*ROI_ShiftRate;
    roi.y = 0;
    roi.width = gray.cols * ROI_WidthRate;
    roi.height = gray.rows;
    
    if (roi.x + roi.width > gray.cols)
        roi.x = 0;
    else if (roi.x + roi.width == gray.cols)
        roi.x -= 1; // slight shift to cover last area
    
    return ErrorOk;
}

Error V2AProcessor::newFrame(const cv::Mat & rgba)
{
    if (rgba.empty())
        DEFINE_check_error(ErrorEmptyMat);
    
    Error err;
    
    cv::cvtColor(rgba, gray, CV_RGBA2GRAY);
    
    cv::Mat gray_roi = gray(roi);
    
    /*
     cv::reduce(gray_c, central_int, 1, CV_REDUCE_AVG); // 1 - single column
     central_int.convertTo(central_res, CV_32F);
    central_res = (cv::Mat_<float>(1,15) << 1., 0., 1., 0.,
                                           2., 0., 0., 0.,
                                           1., 0., 1., 0.,
                                           2., 0., 0., 0.);
     //cv::Mat central_res, central_int, central_fft;
     //int flags = cv::DFT_SCALE;
     //int non_zero_rows = 0;
     //cv::dft(central_res, central_fft, flags, non_zero_rows);
     //*/
    
    /*
    const double MinFreq = 200.;
    const double MaxFreq = 3000.;
    const double FreqRange = MaxFreq - MinFreq;
    const double MaxAmplitude = 3000.;
    
    int col = gray.cols/2;
    int row = gray.rows/2;
    int val = gray.at<uchar>(row, col);
    
    double freq = MinFreq + FreqRange * (1.*row /gray.rows);
    double amplitude = val/255. * MaxAmplitude;
    
    err = sound_gen.playSound(freq, amplitude);
    DEFINE_check_error(err);
    */
    
    const int SourcesCount = int(V2ASoundGenerator::SourcesCount);
    float x_coord = 1.f*(roi.x + roi.width/2) / gray.cols;
    vector<float> ampl_vec(SourcesCount);
    for (int i=0; i<int(ampl_vec.size()); ++i)
    {
        int start_row = i * roi.height / SourcesCount;
        int end_row = min(roi.height, (i+1) * roi.height / SourcesCount);
        cv::Mat gray_segm = gray_roi.rowRange(start_row, end_row);
        double aver = cv::mean(gray_segm)[0];
        ampl_vec[i] = aver;
    }
    err = sound_gen.playSound(ampl_vec, x_coord);
    DEFINE_check_error(err);
    
    err = shiftROI();
    DEFINE_check_error(err);
    
    return ErrorOk;
}

cv::Rect V2AProcessor::getCurrentROI()
{
    return roi;
}
