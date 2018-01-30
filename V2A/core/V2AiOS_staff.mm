#import <Foundation/Foundation.h>
#include "V2AiOS_staff.h"

#include <string>

using namespace std;

NSDictionary * getDictionary()
{
    NSString *path = [[NSBundle mainBundle] pathForResource:@"params" ofType:@"json"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    return [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:nil];
}

bool getBoolParam(NSString * param)
{
    NSDictionary * params = getDictionary();
    return [params[param] boolValue];
}

int getIntParam(NSString * param)
{
    NSDictionary * params = getDictionary();
    return [params[param] intValue];
}

double getDoubleParam(NSString * param)
{
    NSDictionary * params = getDictionary();
    return [params[param] doubleValue];
}

std::string getStringParam(NSString * param)
{
    NSDictionary * params = getDictionary();
    return [params[param] UTF8String];
}


void SLEEP(double ms)
{
    [NSThread sleepForTimeInterval: ms/1e3];
}
