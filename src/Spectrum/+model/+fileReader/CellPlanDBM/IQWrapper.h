#pragma once

#ifndef IQ_WRAPPER_H
#define IQ_WRAPPER_H


#define NOMINMAX

#include <Windows.h>
#include <stdlib.h> 
#include <stdint.h>

#ifdef IQWRAPPER_EXPORTS
#define IQWRAPPER_API __declspec(dllexport)
#else
#define IQWRAPPER_API __declspec(dllimport)
#endif

#define IQ_file_ext	"IQ"
#define dBm_file_ext "DBM"

#ifdef __cplusplus
extern "C" {
#endif

#pragma pack(push, 1)  // Disable padding
typedef struct CapturedRawBuffer_C {
	double latitude;
	double longitude;
	double altitude;

	// SYSTEMTIME_C
	uint16_t year;
	uint16_t month;
	uint16_t dayOfWeek;
	uint16_t day;
	uint16_t hour;
	uint16_t minute;
	uint16_t second;
	uint16_t milliseconds;

	// wsa_packet_time_C
	uint32_t packet_timeStamp_sec;
	uint64_t packet_timeStamp_psec;

	// demais campos
	double ext_NoiseLevelOffset;
	int32_t ext_Tech;
	int32_t ext_Band;
	int32_t ext_Channel;
	double ext_freq;
	double ext_ReducedFreqSpan_MHz;
	double ext_FullFreqSpan_MHz;
	double ext_ResBw_kHz;
	int32_t ext_Decimation;
	int32_t ext_SamplesPerPacket;
	int32_t ext_PacketsPerBlock;
	double ext_ppm;
	int32_t ext_NominalGain;
	int32_t RecordSize;
	int32_t Buffer_nElems;
	int32_t ext_SCS_kHz;
	int32_t DuplexMode;
} CapturedRawBuffer_C;
#pragma pack(pop)


// Funções exportadas pela DLL
IQWRAPPER_API int  IQWrapper_Load_Library(void);
IQWRAPPER_API void IQWrapper_Unload_Library(void);

IQWRAPPER_API int  IQWrapper_OpenFile(char* fname, int* nBlocks);
IQWRAPPER_API void IQWrapper_CloseFile(void);
	
IQWRAPPER_API int  IQWrapper_dBm_NextBlock(CapturedRawBuffer_C* dBm_Buffer, float* dBm, int* BlockNumber, int* length);
IQWRAPPER_API int  IQWrapper_MoreBlocksAvailable(void);

IQWRAPPER_API int  IQWrapper_Get_DLL_Version(void);					// versão da DLL em C++


#ifdef __cplusplus
}
#endif

#endif		// #ifndef IQ_WRAPPER_H
