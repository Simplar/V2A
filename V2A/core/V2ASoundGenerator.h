#ifndef V2ASoundGenerator_h
#define V2ASoundGenerator_h

#include "V2AError.h"
#include <vector>

//!!! documentation

struct ALSource
{
    bool defined;
    unsigned int src;
    unsigned int buf;
    
    ALSource();
};

class V2ASoundGenerator
{
public:
    static const size_t SourcesCount;
    
    V2ASoundGenerator();
    virtual ~V2ASoundGenerator();
    
    Error playSound(double freq, double ampl);
    Error playSound(const std::vector<float> & ampl_vec, float x_coord);

private:
    void *device, *context;
    std::vector<ALSource> sources;
    std::vector<float> freqs;
    std::vector< std::vector<float> > pos_vec;
    float MinFreq, MaxFreq;
    
    // -1 for new source
    Error genSource(unsigned int src_num, double frequency, double amplitude, double seconds);
    
    bool checkSource(unsigned int src_num);
    
    Error playSilence();
    
    Error deleteSource(unsigned int src_num);
    
    char * generateSound(int& chan, int& samplerate, int& bps, int& size, double frequency,
                        double max_amplitude, double seconds = 1);
    Error initBufferAL(unsigned int src_num, double frequency, double amplitude, double seconds);
};

#endif /* V2ASoundGenerator_h */
