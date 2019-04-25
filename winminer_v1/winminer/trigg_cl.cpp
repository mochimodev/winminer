/* trigg_cl.cpp  OpenCL implementation of Trigg's Algorithm
 *
 * Copyright (c) 2019 by Adequate Systems, LLC.  All Rights Reserved.
 * See LICENSE.PDF   **** NO WARRANTY ****
 * https://github.com/mochimodev/mochimo/raw/master/LICENSE.PDF
 *
 * Date: 07 April 2019
 *
*/

#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <tchar.h>

#include "winminer.h"

#include "CL/cl.h"

#include "resource.h"

cl_uint num_devices = 0;
cl_platform_id platform_id = NULL;
cl_device_id device_id[10];

int count_devices_cl() {
	cl_int err;
	cl_uint num_platforms;

	err = clGetPlatformIDs(1, &platform_id, &num_platforms);
	if (CL_SUCCESS != err) {
		printf("clGetPlatformIDs failed. Error: %d\n", err);
		return 0;
	}
	if (num_platforms == 0) {
		printf("No OpenCL platforms detected.\n");
		return 0;
	}
	err = clGetDeviceIDs(platform_id, CL_DEVICE_TYPE_GPU, 10, device_id, &num_devices);
	if (CL_SUCCESS != err) {
		printf("clGetDeviceIDs failed. Error: %d\n", err);
		return 0;
	}
	if (num_devices == 0) {
		printf("No OpenCL devices detected.\n");
		return 0;
	}

	printf("OpenCL: Found %d platforms and %d devices\n", num_platforms, num_devices);

	for (uint32_t i = 0; i < num_devices; i++) {
		size_t len = 0;
		char name[128], vendor[128];
		cl_ulong mem_size = 0;
		err = clGetDeviceInfo(device_id[i], CL_DEVICE_NAME, 128, name, &len);
		if (CL_SUCCESS != err) {
			printf("clGetDeviceInfo failed. Error: %d\n", err);
			continue;
		}
		err = clGetDeviceInfo(device_id[i], CL_DEVICE_VENDOR, 128, vendor, &len);
		if (CL_SUCCESS != err) {
			printf("clGetDeviceInfo failed. Error: %d\n", err);
			continue;
		}
		err = clGetDeviceInfo(device_id[i], CL_DEVICE_GLOBAL_MEM_SIZE, sizeof(mem_size), &mem_size, NULL);
		if (CL_SUCCESS != err) {
			printf("clGetDeviceInfo failed. Error: %d\n", err);
			continue;
		}
		name[127] = '\0';
		vendor[127] = '\0';
		printf("Device %d: %s %s %u MB\n", i, vendor, name, (unsigned int)(mem_size / 1024 / 1024));
	}

	return num_devices;
}

typedef struct __trigg_opencl_ctx {
	byte curr_seed[16], next_seed[16];
	char cp[256], *next_cp;
	int *found;
	cl_mem d_found;
	uint8_t *seed;
	cl_mem d_seed;
	uint32_t *midstate, *input;
	cl_mem d_midstate256, d_input32, d_blockNumber8;
	cl_context context;
	cl_command_queue cq;
	cl_kernel k_trigg;
	cl_event trigg_event;
} TriggCLCTX;

/* Max 64 GPUs Supported */
static TriggCLCTX ctx[64] = {};
static char *nullcp = '\0';
static byte *diff;
static byte *bnum;
static int thrds = 512;
static size_t threads = thrds * 1024 * 1024;
static size_t block = 256;

int trigg_init_cl(byte difficulty, byte *blockNumber) {
	count_devices_cl();
	cl_context_properties properties[] = { CL_CONTEXT_PLATFORM, (cl_context_properties)platform_id, 0 };


	/* Allocate host memory */
	diff = (byte*)malloc(1);
	bnum = (byte*)malloc(8);
	/* Copy immediate block data to pinned memory */
	memcpy(diff, &difficulty, 1);
	memcpy(bnum, blockNumber, 8);

	HRSRC rsc = FindResource(NULL, MAKEINTRESOURCE(IDR_OPENCL_SOURCE1), _T("OPENCL_SOURCE"));
	if (rsc == NULL) {
		DWORD dwErr = GetLastError();
		printf("FindResource failed. Error: %lu\n", dwErr);
	}
	HGLOBAL resGlobal = LoadResource(NULL, rsc);
	char *src = (char*)LockResource(resGlobal);
	DWORD dwSize = SizeofResource(NULL, rsc);
	const char *srcptr = src;
	size_t srcsize = dwSize;

	for (cl_uint i = 0; i < num_devices; i++) {
		cl_int err;
		ctx[i].context = clCreateContext(properties, 1, &(device_id[i]), NULL, NULL, &err);
		if (CL_SUCCESS != err) {
			printf("clCreateContext failed. Error: %d\n", err);
		}
		ctx[i].cq = clCreateCommandQueue(ctx[i].context, device_id[i], 0, &err);
		if (CL_SUCCESS != err) {
			printf("clCreateCommandQueue failed. Error: %d\n", err);
		}

		cl_program prog = clCreateProgramWithSource(ctx[i].context, 1, &srcptr, &srcsize, &err);
		if (CL_SUCCESS != err) {
			printf("clCreateProgramWithSource failed. Error: %d\n", err);
		}
		err = clBuildProgram(prog, 0, NULL, "", NULL, NULL);
		if (CL_SUCCESS != err) {
			printf("clBuildProgram failed. Error: %d\n", err);
		}
		if (err == CL_BUILD_PROGRAM_FAILURE) {
			// Determine the size of the log
			size_t log_size;
			clGetProgramBuildInfo(prog, device_id[0], CL_PROGRAM_BUILD_LOG, 0, NULL, &log_size);

			// Allocate memory for the log
			char *log = (char *)malloc(log_size);

			// Get the log
			clGetProgramBuildInfo(prog, device_id[0], CL_PROGRAM_BUILD_LOG, log_size, log, NULL);

			// Print the log
			printf("%s\n", log);
		}

		ctx[i].k_trigg = clCreateKernel(prog, "trigg", &err);
		if (CL_SUCCESS != err) {
			printf("clCreateKernel failed. Error: %d\n", err);
		}

		/* Allocate device memory */
		ctx[i].d_found = clCreateBuffer(ctx[i].context, CL_MEM_WRITE_ONLY, 4, NULL, &err);
		if (CL_SUCCESS != err) {
			printf("clCreateBuffer failed. Error: %d\n", err);
		}
		ctx[i].d_seed = clCreateBuffer(ctx[i].context, CL_MEM_WRITE_ONLY, 16, NULL, &err);
		if (CL_SUCCESS != err) {
			printf("clCreateBuffer failed. Error: %d\n", err);
		}
		ctx[i].d_midstate256 = clCreateBuffer(ctx[i].context, CL_MEM_READ_ONLY, 32, NULL, &err);
		if (CL_SUCCESS != err) {
			printf("clCreateBuffer failed. Error: %d\n", err);
		}
		ctx[i].d_input32 = clCreateBuffer(ctx[i].context, CL_MEM_READ_ONLY, 32, NULL, &err);
		if (CL_SUCCESS != err) {
			printf("clCreateBuffer failed. Error: %d\n", err);
		}
		ctx[i].d_blockNumber8 = clCreateBuffer(ctx[i].context, CL_MEM_READ_ONLY, 8, NULL, &err);
		if (CL_SUCCESS != err) {
			printf("clCreateBuffer failed. Error: %d\n", err);
		}

		err = clSetKernelArg(ctx[i].k_trigg, 0, 4, &threads);
		if (CL_SUCCESS != err) {
			printf("%s:%d: clSetKernelArg failed. Error: %d\n", __FILE__, __LINE__, err);
		}
		err = clSetKernelArg(ctx[i].k_trigg, 1, sizeof(cl_mem), &ctx[i].d_found);
		if (CL_SUCCESS != err) {
			printf("%s:%d: clSetKernelArg failed. Error: %d\n", __FILE__, __LINE__, err);
		}
		err = clSetKernelArg(ctx[i].k_trigg, 2, sizeof(cl_mem), &ctx[i].d_seed);
		if (CL_SUCCESS != err) {
			printf("%s:%d: clSetKernelArg failed. Error: %d\n", __FILE__, __LINE__, err);
		}
		err = clSetKernelArg(ctx[i].k_trigg, 3, sizeof(cl_mem), &ctx[i].d_midstate256);
		if (CL_SUCCESS != err) {
			printf("%s:%d: clSetKernelArg failed. Error: %d\n", __FILE__, __LINE__, err);
		}
		err = clSetKernelArg(ctx[i].k_trigg, 4, sizeof(cl_mem), &ctx[i].d_input32);
		if (CL_SUCCESS != err) {
			printf("%s:%d: clSetKernelArg failed. Error: %d\n", __FILE__, __LINE__, err);
		}
		err = clSetKernelArg(ctx[i].k_trigg, 5, sizeof(cl_mem), &ctx[i].d_blockNumber8);
		if (CL_SUCCESS != err) {
			printf("%s:%d: clSetKernelArg failed. Error: %d\n", __FILE__, __LINE__, err);
		}

		/* Allocate associated device-host memory */
		ctx[i].found = (int*)malloc(4);
		ctx[i].seed = (uint8_t*)malloc(16);
		ctx[i].midstate = (uint32_t*)malloc(32);
		ctx[i].input = (uint32_t*)malloc(32);
		/* Set remaining device memory */
		err = clEnqueueFillBuffer(ctx[i].cq, ctx[i].d_found, "\0", 1, 0, 4, 0, NULL, NULL);
		if (CL_SUCCESS != err) {
			printf("clEnqueueFillBuffer failed. Error: %d\n", err);
		}
		err = clEnqueueFillBuffer(ctx[i].cq, ctx[i].d_seed, "\0", 1, 0, 16, 0, NULL, NULL);
		if (CL_SUCCESS != err) {
			printf("clEnqueueFillBuffer failed. Error: %d\n", err);
		}
		/* Setup variables for "first round" */
		*ctx[i].found = 0;
		ctx[i].next_cp = nullcp;
		printf("\nTrace: GPU %d Initialized.", i);
	}

	return num_devices;
}

void trigg_free_cl() {
	free(diff);
	free(bnum);

	for (cl_uint i = 0; i < num_devices; i++) {
		cl_int err = clReleaseMemObject(ctx[i].d_found);
		if (CL_SUCCESS != err) {
			printf("clReleaseMemObject failed. Error: %d\n", err);
		}
		err = clReleaseMemObject(ctx[i].d_seed);
		if (CL_SUCCESS != err) {
			printf("clReleaseMemObject failed. Error: %d\n", err);
		}
		err = clReleaseMemObject(ctx[i].d_midstate256);
		if (CL_SUCCESS != err) {
			printf("clReleaseMemObject failed. Error: %d\n", err);
		}
		err = clReleaseMemObject(ctx[i].d_input32);
		if (CL_SUCCESS != err) {
			printf("clReleaseMemObject failed. Error: %d\n", err);
		}
		err = clReleaseMemObject(ctx[i].d_blockNumber8);
		if (CL_SUCCESS != err) {
			printf("clReleaseMemObject failed. Error: %d\n", err);
		}

		err = clReleaseCommandQueue(ctx[i].cq);
		if (CL_SUCCESS != err) {
			printf("clReleaseCommandQueue failed. Error: %d\n", err);
		}
		err = clReleaseKernel(ctx[i].k_trigg);
		if (CL_SUCCESS != err) {
			printf("clReleaseKernel failed. Error: %d\n", err);
		}
		err = clReleaseContext(ctx[i].context);
		if (CL_SUCCESS != err) {
			printf("clReleaseContext failed. Error: %d\n", err);
		}
	}
}


char *trigg_generate_cl(byte *mroot, uint32_t *nHaiku) {
	cl_int err;
	cl_uint i;

	for (i = 0; i < num_devices; i++) {
#ifdef CL_DEBUG
		Sleep(50);
		printf("\n\n\n");
#endif
		/*printf("\nFound value is:  %d", *ctx[i].found);*/
		/* If next_cp is empty... */
		if (ctx[i].next_cp == nullcp) {
			/* ... init GPU seeds */
			trigg_gen(ctx[i].next_seed);
			ctx[i].next_cp = trigg_expand(ctx[i].next_seed, *diff);
			/* ... copy mroot to Tchain */
			memcpy(Tchain, mroot, 32);
			/* ... and prepare sha256 midstate for next round */
			SHA256_CTX sha256;
			sha256_init(&sha256);
			sha256_update(&sha256, Tchain, 256);
			memcpy(ctx[i].midstate, sha256.state, 32);
			memcpy(ctx[i].input, Tchain + 256, 32);
		}
#ifdef CL_DEBUG
		memset(ctx[i].midstate, 0, 32);
		memset(ctx[i].input, 0, 32);
		memset(bnum, 0, 8);
		printf("input: "); for (int j = 0; j < 8; j++) { printf("%08x ", ctx[i].input[j]); } printf("\n");
#endif
		cl_int status = -1;
		if (ctx[i].trigg_event != NULL) {
			err = clGetEventInfo(ctx[i].trigg_event, CL_EVENT_COMMAND_EXECUTION_STATUS, sizeof(cl_int), &status, NULL);
			if (CL_SUCCESS != err) {
				printf("clGetEventInfo failed. Error: %d\n", err);
			}
			if (status == CL_COMPLETE) {
				err = clEnqueueReadBuffer(ctx[i].cq, ctx[i].d_found, CL_TRUE, 0, 4, ctx[i].found, 0, NULL, NULL);
				if (CL_SUCCESS != err) {
					printf("%s:%d: clEnqueueReadBuffer failed. Error: %d\n", __FILE__, __LINE__, err);
				}
			}
		}
#ifdef CL_DEBUG
		printf("ctx[i].found = %d\n", *ctx[i].found);
#endif
		/** Due to the asynchronous nature of this process,
		 ** conditions below MUST be performed in order of
		 ** found status (-1) to (1), so a solve isn't "missed" **/

		 /* Waiting on GPU || *ctx[i].found == -1 */
		if (*ctx[i].found < 0) continue;

		/* GPU is done. NO SOLVE || *ctx[i].found == 0 From First Run */
		if (*ctx[i].found < 1) {
			/* Start new GPU round */
			err = clEnqueueWriteBuffer(ctx[i].cq, ctx[i].d_midstate256, CL_FALSE, 0, 32, ctx[i].midstate, 0, NULL, NULL);
			if (CL_SUCCESS != err) {
				printf("%s:%d: clEnqueueWriteBuffer failed. Error: %d\n", __FILE__, __LINE__, err);
			}
			err = clEnqueueWriteBuffer(ctx[i].cq, ctx[i].d_input32, CL_FALSE, 0, 32, ctx[i].input, 0, NULL, NULL);
			if (CL_SUCCESS != err) {
				printf("%s:%d: clEnqueueWriteBuffer failed. Error: %d\n", __FILE__, __LINE__, err);
			}
			err = clEnqueueWriteBuffer(ctx[i].cq, ctx[i].d_blockNumber8, CL_FALSE, 0, 8, bnum, 0, NULL, NULL);
			if (CL_SUCCESS != err) {
				printf("%s:%d: clEnqueueWriteBuffer failed. Error: %d\n", __FILE__, __LINE__, err);
			}

			err = clSetKernelArg(ctx[i].k_trigg, 6, 1, diff);
			if (CL_SUCCESS != err) {
				printf("%s:%d: clSetKernelArg failed. Error: %d\n", __FILE__, __LINE__, err);
			}

			err = clEnqueueNDRangeKernel(ctx[i].cq, ctx[i].k_trigg, 1, NULL, &threads, &block, 0, NULL, &ctx[i].trigg_event);
			if (CL_SUCCESS != err) {
				printf("%s:%d: clEnqueueNDRangeKernel failed. Error: %d\n", __FILE__, __LINE__, err);
			}
#ifdef CL_DEBUG
			printf("started kernel\n");
			err = clFinish(cq);
			if (CL_SUCCESS != err) {
				printf("clFinish failed. Error: %d\n", err);
			}
			printf("kernel done\n");
			Sleep(1000);
#endif

			/* Set GPU waiting status and add to haiku count */
			*nHaiku += thrds;
			*ctx[i].found = -1;

			/* Store round vars aside for checks next loop */
			memcpy(ctx[i].curr_seed, ctx[i].next_seed, 16);
			strcpy(ctx[i].cp, ctx[i].next_cp);
			ctx[i].next_cp = nullcp;
			continue;
		}

		/* GPU is done. SOLVED! || *ctx[i].found == 1 */
		err = clEnqueueReadBuffer(ctx[i].cq, ctx[i].d_seed, CL_TRUE, 0, 16, ctx[i].seed, 0, NULL, NULL);
		if (CL_SUCCESS != err) {
			printf("%s:%d: clEnqueueReadBuffer failed. Error: %d\n", __FILE__, __LINE__, err);
		}
		memcpy(mroot + 32, ctx[i].curr_seed, 16);
		memcpy(mroot + 32 + 16, ctx[i].seed, 16);
		return ctx[i].cp;
	}

	return NULL;
}