#ifndef SERROR_H_INCLUDED
#define SERROR_H_INCLUDED

#include <string>
#include <iostream>

extern bool GlobalDebugMode;

enum Error
{
	ErrorOk 				 = 0,		// No error
	ErrorEmptyMat 			 = 1,		// Source mat is empty
	ErrorReadFile 			 = 2,		// Cannot read file
	ErrorChannels            = 3,       // Wrong number of channels in Mat
    ErrorNotInitialized		 = 4,		// Something should be initialized but was not initialized
    ErrorWrongParameters	 = 5,		// Unexpected numerical parameters
    ErrorAL                  = 6        // Error in OpenAL framework
};

#define GET_VARIABLE_NAME(Variable) (#Variable)

inline Error print_error(Error err, const std::string & err_str, const std::string & file, int line)
{
    if( GlobalDebugMode )
        std::cout << err_str << " in " << file << " at line " << line << std::endl;
	return err;
}

inline std::string filename_only(const std::string & path_to_file)
{
	int pos = std::max(0, std::max(int(path_to_file.find_last_of('/')),
								   int(path_to_file.find_last_of('\\'))) );
	return path_to_file.substr(pos+1);
}

/********************************************//**
 * \brief Define to return error and print its location
 ***********************************************/
#define DEFINE_check_error( err ) 					\
		{				 							\
			if( err != ErrorOk )					\
				return print_error(err, GET_VARIABLE_NAME(err), filename_only(__FILE__), __LINE__);	\
		}

#endif // SERROR_H_INCLUDED
