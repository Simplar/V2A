#ifndef V2AiOS_staff_h
#define V2AiOS_staff_h

@class NSString;
#include <string>

bool getBoolParam(NSString * param);
int getIntParam(NSString * param);
double getDoubleParam(NSString * param);
std::string getStringParam(NSString * param);

void SLEEP(double ms);

#endif /* V2AiOS_staff_h */
