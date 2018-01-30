#include "V2ASoundGenerator.h"

// iOS
#ifdef __APPLE__
#include <OpenAl/al.h>
#include <OpenAl/alc.h>
#include "V2AiOS_staff.h"
#endif

// Windows
#if defined(_WIN32) || defined(_WIN64)
#define SLEEP(ms) sleep(ms)
#endif

#include <cmath>
#include <fstream>
#include <iostream>

//*
#define DEFINE_check_error_AL DEFINE_check_error( (alGetError()==AL_NO_ERROR ? ErrorOk : ErrorAL) )
/*/
inline Error print_error(Error err, int err_str, const std::string & file, int line)
{
    if( GlobalDebugMode )
        std::cout << err_str << " err_str " << file << " at line " << line << std::endl;
    return err;
}

#define DEFINE_check_error_AL \
{\
    ALenum err = alGetError(); \
    if (err == AL_NO_ERROR) DEFINE_check_error(ErrorOk); \
    else print_error(ErrorAL, int(err), filename_only(__FILE__), __LINE__); \
}\
//*/

using namespace std;

#define kSilenceSource 0 //!!! delete if not needed
#define PI     3.14159265359
#define TWO_PI 6.28318530718

const size_t V2ASoundGenerator::SourcesCount = 31; // 31

ALSource::ALSource()
{
    defined = false;
    src = 0;
    buf = 0;
}

V2ASoundGenerator::V2ASoundGenerator()
{
    // Sound card recognizing
    device = alcOpenDevice(NULL);
    if (device == NULL)
    {
        cout << "Cannot open sound card" << endl;
        return;
    }
    
    // Context creation
    context = alcCreateContext( (ALCdevice*)device, NULL);
    if (context == NULL)
    {
        cout << "Cannot open context" << endl;
        return;
    }
    
    // Setting current context
    alcMakeContextCurrent( (ALCcontext*)context );
    
    // Init sources array;
    sources.resize(SourcesCount);
    
    // Init sources positions and frequencies
    MinFreq = 700.;
    MaxFreq = 4000.;
    
    pos_vec.resize(SourcesCount);
    freqs.resize(SourcesCount);
    for (size_t i=0; i<SourcesCount; ++i)
    {
        pos_vec[i].resize(3);
        float y_coord = SourcesCount > 1 ? 1.f * i / (SourcesCount-1) : 0.f;
        pos_vec[i][1] = sin( (y_coord - 0.5) * PI ); // -PI/2 .. PI/2
        pos_vec[i][2] = 1.; //!!! ?
        if (SourcesCount > 1)
            freqs[i] = MinFreq + (1.f * (SourcesCount-1 - i) / (SourcesCount-1) ) * (MaxFreq - MinFreq); // MinFreq..MaxFreq
        else
            freqs[i] = (MinFreq + MaxFreq) / 2.;
    }
    
    return;
    
    //!!! delete if not needed
    // Generate silency source
    Error err;
    err = genSource(kSilenceSource, 0, 0, 1);
    if (err != ErrorOk)
    {
        print_error(ErrorAL, "Cannot generate silence source", __FILE__, __LINE__);
    }
}

V2ASoundGenerator::~V2ASoundGenerator()
{
    for(size_t i=0; i<sources.size(); ++i)
    {
        alDeleteSources(1, &sources[i].src);
        alDeleteBuffers(1, &sources[i].buf);
    }
    
    alcCloseDevice( (ALCdevice*)device );
    alcDestroyContext( (ALCcontext*)context );
}

Error V2ASoundGenerator::deleteSource(unsigned int src_num)
{
    alSourceStop(sources[src_num].src);         DEFINE_check_error_AL; //!!! check if needed
    alDeleteSources(1, &sources[src_num].src);  DEFINE_check_error_AL;
    alDeleteBuffers(1, &sources[src_num].buf);  DEFINE_check_error_AL;
    sources[src_num].defined = false;
    
    return ErrorOk;
}

Error V2ASoundGenerator::playSilence()
{
    if (!checkSource(kSilenceSource))
        DEFINE_check_error(ErrorNotInitialized);
    
    alSourcePlay(sources[kSilenceSource].src);
    DEFINE_check_error_AL;
    
    return ErrorOk;
}

bool V2ASoundGenerator::checkSource(unsigned int src_num)
{
    return src_num<sources.size() && sources[src_num].defined; //!!! check if source found and buffer found
}

char * V2ASoundGenerator::generateSound(int& chan, int& samplerate, int& bps, int& size, double frequency,
                                        double max_amplitude, double seconds)
{
    chan = 1;
    samplerate = 44100; //22050;//44100;
    bps = 16;
    
    //constexpr double max_amplitude = 32760;  // "volume"
    
    const int SamplesCount = samplerate * seconds;  // total number of samples
    
    size = int(samplerate * seconds*2);
    //int* data = new int[size];
    char* data = new char[size];
    for (int i=0; i<SamplesCount; ++i)
    {
        double offs = 0.1;
        double amplitude = max_amplitude;
        
        // sound fading to exclude cracking
        if (i < SamplesCount * offs)        amplitude *= i / (SamplesCount * offs);
        if (i > SamplesCount * (1-offs))    amplitude *= (SamplesCount - i) / (SamplesCount * offs);
       
        int val = amplitude * sin( (2.f*float(M_PI) * i * int(frequency)) / samplerate );
        unsigned char * ch = (unsigned char*)(&val);
        data[i*2] = ch[0];
        data[i*2+1] = ch[1];
    }
    
    return (char*)data;
}

Error V2ASoundGenerator::initBufferAL(unsigned int src_num, double frequency, double amplitude, double seconds)
{
    int channel, sampleRate, bps, size;
    char * data = generateSound(channel, sampleRate, bps, size, frequency, amplitude, seconds);
    
    alGenBuffers(1, &sources[src_num].buf);
    DEFINE_check_error_AL;
    unsigned int format;
    
    if (channel == 1)
        format = (bps == 8) ? AL_FORMAT_MONO8 : AL_FORMAT_MONO16;
    else
        format = (bps == 8) ? AL_FORMAT_STEREO8 : AL_FORMAT_STEREO16;
    
    alBufferData(sources[src_num].buf, format, data, size, sampleRate);
    DEFINE_check_error_AL;
    delete[] data;
    
    alSourcei(sources[src_num].src, AL_BUFFER, sources[src_num].buf);
    DEFINE_check_error_AL;
    
    return ErrorOk;
}

Error V2ASoundGenerator::genSource(unsigned int src_num, double frequency, double amplitude, double seconds)
{
    if (src_num > sources.size())
        DEFINE_check_error( ErrorWrongParameters );
 
    Error err;
    
    if ( checkSource(src_num) )
    {
        err = deleteSource(src_num);
        DEFINE_check_error(err);
    }
    //else
    {alGenSources(1, &sources[src_num].src); DEFINE_check_error_AL;}
    sources[src_num].defined = true;
    
    err = initBufferAL(src_num, frequency, amplitude, seconds);
    DEFINE_check_error( err );
    
    return ErrorOk;
}

Error V2ASoundGenerator::playSound(double freq, double ampl)
{
    Error err;
    unsigned int src_num = 1;
    double duration_seconds = 0.03;
    err = genSource(src_num, freq, ampl, duration_seconds);
    DEFINE_check_error(err);
    
    ALint src_state;
    alGetSourcei(sources[src_num].src, AL_SOURCE_STATE, &src_state);
    DEFINE_check_error_AL;
    
    //alSourcei(sources[src_num].src, AL_LOOPING, 1);
    
    if (src_state == AL_INITIAL)
    {
        alSourcePlay(sources[src_num].src);
        DEFINE_check_error_AL;
        
        alSource3f(sources[src_num].src, AL_POSITION, 0, 0, 0);
        DEFINE_check_error_AL;
    }
    
    SLEEP(duration_seconds * 1e3);
    
    return ErrorOk;
}

Error V2ASoundGenerator::playSound(const std::vector<float> & ampl_vec, float x_coord)
{
    if (x_coord < 0.f || x_coord > 1.f)
        DEFINE_check_error(ErrorWrongParameters);
    if (ampl_vec.size() != SourcesCount)
        DEFINE_check_error(ErrorWrongParameters);
    
    Error err;
    double duration_seconds = .03;
    
    float x_pos = sin( (x_coord - 0.5) * PI );
    for (unsigned int src_num = 0; src_num < SourcesCount; ++src_num)
    {
        pos_vec[src_num][0] = x_pos;
        
        err = genSource(src_num, freqs[src_num], ampl_vec[src_num], duration_seconds);
        DEFINE_check_error(err);
        
        ALint src_state;
        alGetSourcei(sources[src_num].src, AL_SOURCE_STATE, &src_state);
        DEFINE_check_error_AL;
        
        //cout << "src_num: " << src_num << endl;
        if (src_state == AL_INITIAL)
        {
            alSource3f(sources[src_num].src, AL_POSITION, pos_vec[src_num][0], pos_vec[src_num][1], pos_vec[src_num][2]); DEFINE_check_error_AL;
            
            alSourcePlay(sources[src_num].src); DEFINE_check_error_AL;
        }
    }
    SLEEP(duration_seconds * 1e3);
    
    return ErrorOk;
}

