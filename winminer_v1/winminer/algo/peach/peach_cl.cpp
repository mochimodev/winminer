/* peach_cl.cpp  OpenCL implementation of peach algorithm
 *
 * Copyright (c) 2019 by Adequate Systems, LLC.  All Rights Reserved.
 * See LICENSE.PDF   **** NO WARRANTY ****
 * https://github.com/mochimodev/mochimo/raw/master/LICENSE.PDF
 *
 * Date: 02 September 2019
 *
*/

#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <tchar.h>

#include "../../winminer.h"

#include <CL/cl.h>

#include "../../resource.h"
#include "../../sleep.h"
#include "../../helpers.h"

#include "../../config.h"

#include "peach.h"

cl_uint num_devices = 0;
cl_platform_id platform_id = NULL;
cl_device_id device_id[10];

cl_program opencl_compile_source(cl_context context, uint8_t num_devices, cl_device_id *devices, int resource_number, const char *options) {
	printf("Compiling: %d\n", resource_number);
	HRSRC rsc = FindResource(NULL, MAKEINTRESOURCE(resource_number), _T("OPENCL_SOURCE"));
	if (rsc == NULL) {
		DWORD dwErr = GetLastError();
		printf("FindResource failed. Error: %lu\n", dwErr);
	}
	HGLOBAL resGlobal = LoadResource(NULL, rsc);
	char *src = (char*)LockResource(resGlobal);
	DWORD dwSize = SizeofResource(NULL, rsc);

	const char *srcptr = src;
	size_t srcsize = dwSize;

	cl_int err;
	cl_program prog = clCreateProgramWithSource(context, 1, &srcptr, &srcsize, &err);
	if (CL_SUCCESS != err) {
		printf("clCreateProgramWithSource failed. Error: %d\n", err);
		exit(1);
	}
	err = clCompileProgram(prog, num_devices, devices, options, 0, NULL, NULL, NULL, NULL);
	if (CL_SUCCESS != err) {
		printf("clCompileProgram failed. Error: %d\n", err);
		if (err == CL_COMPILE_PROGRAM_FAILURE || err == CL_BUILD_PROGRAM_FAILURE) {
			// Determine the size of the log
			size_t log_size;
			clGetProgramBuildInfo(prog, devices[0], CL_PROGRAM_BUILD_LOG, 0, NULL, &log_size);

			// Allocate memory for the log
			char *log = (char *)malloc(log_size);

			// Get the log
			clGetProgramBuildInfo(prog, devices[0], CL_PROGRAM_BUILD_LOG, log_size, log, NULL);

			// Print the log
			printf("Log:\n");
			printf("%s\n", log);
			free(log);
		}
		exit(1);
	}

	//free(src);

	return prog;
}

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

typedef struct __peach_opencl_ctx {
	byte init;
	byte curr_seed[16], next_seed[16];
	char cp[256], *next_cp;
	int *found;
	cl_mem d_map;
	cl_mem d_phash;
	cl_mem d_found;
	uint8_t *seed;
	cl_mem d_seed;
	uint8_t *input;
	cl_mem d_input, d_blockNumber8;
	cl_context context;
	cl_command_queue cq;
	cl_kernel k_peach;
	cl_kernel k_peach_build;
	cl_event trigg_event;
	int64_t t_start, t_end;
	uint32_t hps[3];
	uint8_t hps_index;
	uint32_t ahps;
} PeachCLCTX;

/* Max 64 GPUs Supported */
static PeachCLCTX ctx[64] = {};
static char *nullcp = '\0';
static byte *diff;
static byte bnum[8] = { 0 };
static byte *phash;
static size_t threads = 512*256;
static size_t block = 256;
static byte gpuInit = 0;

int peach_init_cl(byte difficulty, byte *prevhash, byte *blocknumber) {
	count_devices_cl();
	cl_context_properties properties[] = { CL_CONTEXT_PLATFORM, (cl_context_properties)platform_id, 0 };


	/* Allocate host memory */
	diff = (byte*)malloc(1);
	phash = (byte*)malloc(32);
	/* Copy immediate block data to pinned memory */
	*diff = difficulty;
	memcpy(phash, prevhash, 32);

	if (gpuInit == 0) {
		gpuInit = 1;
		for (cl_uint i = 0; i < num_devices; i++) {
			ctx[i].init = 0;
		}
	}

	for (cl_uint i = 0; i < num_devices; i++) {
		cl_int err;
		if (ctx[i].init == 0) {
			ctx[i].context = clCreateContext(properties, 1, &(device_id[i]), NULL, NULL, &err);
			if (CL_SUCCESS != err) {
				printf("clCreateContext failed. Error: %d\n", err);
				return -1;
			}
			ctx[i].cq = clCreateCommandQueue(ctx[i].context, device_id[i], 0, &err);
			if (CL_SUCCESS != err) {
				printf("clCreateCommandQueue failed. Error: %d\n", err);
				return -1;
			}

			cl_program prog_md5 = opencl_compile_source(ctx[i].context, 1, &device_id[i], IDR_OPENCL_MD5, "-cl-fp32-correctly-rounded-divide-sqrt");
			cl_program prog_sha1 = opencl_compile_source(ctx[i].context, 1, &device_id[i], IDR_OPENCL_SHA1, "-cl-fp32-correctly-rounded-divide-sqrt");
			cl_program prog_sha256 = opencl_compile_source(ctx[i].context, 1, &device_id[i], IDR_OPENCL_SHA256, "-cl-fp32-correctly-rounded-divide-sqrt");
			cl_program prog_md2 = opencl_compile_source(ctx[i].context, 1, &device_id[i], IDR_OPENCL_MD2, "-cl-fp32-correctly-rounded-divide-sqrt");
			cl_program prog_keccak = opencl_compile_source(ctx[i].context, 1, &device_id[i], IDR_OPENCL_KECCAK, "-cl-fp32-correctly-rounded-divide-sqrt");
			cl_program prog_blake2b = opencl_compile_source(ctx[i].context, 1, &device_id[i], IDR_OPENCL_BLAKE2B, "-cl-fp32-correctly-rounded-divide-sqrt");
			cl_program prog_peach = opencl_compile_source(ctx[i].context, 1, &device_id[i], IDR_OPENCL_PEACH, "-cl-fp32-correctly-rounded-divide-sqrt");
			cl_program prog_parts[] = { prog_peach, prog_md5, prog_sha1, prog_sha256, prog_md2, prog_keccak, prog_blake2b };
			cl_program prog = clLinkProgram(ctx[i].context, 1, &device_id[0], NULL, 7, prog_parts, NULL, NULL, &err);
			if (CL_SUCCESS != err) {
				printf("clLinkProgram failed. Error: %d\n", err);
				return -1;
			}

			ctx[i].k_peach_build = clCreateKernel(prog, "cl_build_map", &err);
			if (CL_SUCCESS != err) {
				printf("clCreateKernel failed. Error: %d\n", err);
				return -1;
			}

			ctx[i].k_peach = clCreateKernel(prog, "cl_find_peach", &err);
			if (CL_SUCCESS != err) {
				printf("clCreateKernel failed. Error: %d\n", err);
				return -1;
			}

			/* Allocate device memory */
			ctx[i].d_map = clCreateBuffer(ctx[i].context, CL_MEM_READ_WRITE, MAP_LENGTH, NULL, &err);
			if (CL_SUCCESS != err) {
				printf("clCreateBuffer failed. Error: %d\n", err);
				return -1;
			}

			ctx[i].d_phash = clCreateBuffer(ctx[i].context, CL_MEM_READ_ONLY, 32, NULL, &err);
			if (CL_SUCCESS != err) {
				printf("clCreateBuffer failed. Error: %d\n", err);
				return -1;
			}

			ctx[i].d_found = clCreateBuffer(ctx[i].context, CL_MEM_WRITE_ONLY, 4, NULL, &err);
			if (CL_SUCCESS != err) {
				printf("clCreateBuffer failed. Error: %d\n", err);
				return -1;
			}
			ctx[i].d_seed = clCreateBuffer(ctx[i].context, CL_MEM_WRITE_ONLY, 16, NULL, &err);
			if (CL_SUCCESS != err) {
				printf("clCreateBuffer failed. Error: %d\n", err);
				return -1;
			}
			ctx[i].d_input = clCreateBuffer(ctx[i].context, CL_MEM_READ_ONLY, 108, NULL, &err);
			if (CL_SUCCESS != err) {
				printf("clCreateBuffer failed. Error: %d\n", err);
				return -1;
			}
			ctx[i].d_blockNumber8 = clCreateBuffer(ctx[i].context, CL_MEM_READ_ONLY, 8, NULL, &err);
			if (CL_SUCCESS != err) {
				printf("clCreateBuffer failed. Error: %d\n", err);
				return -1;
			}

			/* Allocate associated device-host memory */
			ctx[i].found = (int*)malloc(4);
			ctx[i].seed = (uint8_t*)malloc(16);
			ctx[i].input = (uint8_t*)malloc(108);

			ctx[i].init = 1;
		}

		err = clSetKernelArg(ctx[i].k_peach, 5, 1, diff);
		if (CL_SUCCESS != err) {
			printf("%s:%d: clSetKernelArg failed. Error: %d\n", __FILE__, __LINE__, err);
		}

		err = clEnqueueWriteBuffer(ctx[i].cq, ctx[i].d_phash, CL_FALSE, 0, 32, phash, 0, NULL, NULL);
		if (CL_SUCCESS != err) {
			printf("%s:%d: clEnqueueWriteBuffer failed. Error: %d\n", __FILE__, __LINE__, err);
			return -1;
		}

		err = clEnqueueFillBuffer(ctx[i].cq, ctx[i].d_found, "\0", 1, 0, 4, 0, NULL, NULL);
		if (CL_SUCCESS != err) {
			printf("clEnqueueFillBuffer failed. Error: %d\n", err);
		}

		err = clEnqueueFillBuffer(ctx[i].cq, ctx[i].d_seed, "\0", 1, 0, 16, 0, NULL, NULL);
		if (CL_SUCCESS != err) {
			printf("clEnqueueFillBuffer failed. Error: %d\n", err);
		}

		ctx[i].next_seed[0] = 0;


		err = clSetKernelArg(ctx[i].k_peach, 0, 4, &threads);
		if (CL_SUCCESS != err) {
			printf("%s:%d: clSetKernelArg failed. Error: %d\n", __FILE__, __LINE__, err);
		}
		err = clSetKernelArg(ctx[i].k_peach, 1, sizeof(cl_mem), &ctx[i].d_map);
		if (CL_SUCCESS != err) {
			printf("%s:%d: clSetKernelArg failed. Error: %d\n", __FILE__, __LINE__, err);
		}
		err = clSetKernelArg(ctx[i].k_peach, 2, sizeof(cl_mem), &ctx[i].d_found);
		if (CL_SUCCESS != err) {
			printf("%s:%d: clSetKernelArg failed. Error: %d\n", __FILE__, __LINE__, err);
		}
		err = clSetKernelArg(ctx[i].k_peach, 3, sizeof(cl_mem), &ctx[i].d_seed);
		if (CL_SUCCESS != err) {
			printf("%s:%d: clSetKernelArg failed. Error: %d\n", __FILE__, __LINE__, err);
		}
		err = clSetKernelArg(ctx[i].k_peach, 4, sizeof(cl_mem), &ctx[i].d_input);
		if (CL_SUCCESS != err) {
			printf("%s:%d: clSetKernelArg failed. Error: %d\n", __FILE__, __LINE__, err);
		}

		/* (re)Build map if new block */
		if (memcmp(bnum, blocknumber, 8) != 0) {
			err = clSetKernelArg(ctx[i].k_peach_build, 0, sizeof(cl_mem), &ctx[i].d_map);
			if (CL_SUCCESS != err) {
				printf("%s:%d: clSetKernelArg failed. Error: %d\n", __FILE__, __LINE__, err);
			}
			err = clSetKernelArg(ctx[i].k_peach_build, 1, sizeof(cl_mem), &ctx[i].d_phash);
			if (CL_SUCCESS != err) {
				printf("%s:%d: clSetKernelArg failed. Error: %d\n", __FILE__, __LINE__, err);
			}
			err = clFinish(ctx[i].cq);
			if (CL_SUCCESS != err) {
				printf("clFinish failed. Error: %d\n", err);
			}
			cl_ulong size;
			clGetDeviceInfo(device_id[0], CL_DEVICE_LOCAL_MEM_SIZE, sizeof(cl_ulong), &size, 0);
			printf("CL_DEVICE_LOCAL_MEM_SIZE: %ld\n", size);
			printf("Running build_map\n");
			size_t build_map_work_size = 4096;
			size_t build_map_local_size = 256;
			for (int z = 0; z < 256; z++) {
				uint32_t start_index = z * 4096;
				err = clSetKernelArg(ctx[i].k_peach_build, 2, sizeof(uint32_t), &start_index);
				if (CL_SUCCESS != err) {
					printf("%s:%d: clSetKernelArg failed. Error: %d\n", __FILE__, __LINE__, err);
				}
				err = clEnqueueNDRangeKernel(ctx[i].cq, ctx[i].k_peach_build, 1, NULL, &build_map_work_size, &build_map_local_size, 0, NULL, &ctx[i].trigg_event);
				if (CL_SUCCESS != err) {
					printf("%s:%d: clEnqueueNDRangeKernel failed. Error: %d\n", __FILE__, __LINE__, err);
				}
			}
			err = clFinish(ctx[i].cq);
			if (CL_SUCCESS != err) {
				printf("clFinish failed. Error: %d\n", err);
			}

			printf("Build_map complete\n");
		}
	}

	/* Check for any GPU initialization errors */
	for (cl_uint i = 0; i < num_devices; i++) {
		printf("Wait for synchronization of cl_build_map\n");
		cl_int err = clFinish(ctx[i].cq);
		if (CL_SUCCESS != err) {
			printf("clFinish failed. Error: %d\n", err);
			return -1;
		}
	}

	/* Update block number */
	memcpy(bnum, blocknumber, 8);

	printf("Returning %d gpus\n", num_devices);

	return num_devices;
}

void peach_free_cl() {
	free(diff);
	free(bnum);

	for (cl_uint i = 0; i < num_devices; i++) {
		ctx[i].init = 0;

		cl_int err = clReleaseMemObject(ctx[i].d_found);
		if (CL_SUCCESS != err) {
			printf("clReleaseMemObject failed. Error: %d\n", err);
		}
		err = clReleaseMemObject(ctx[i].d_map);
		if (CL_SUCCESS != err) {
			printf("clReleaseMemObject failed. Error: %d\n", err);
		}
		err = clReleaseMemObject(ctx[i].d_phash);
		if (CL_SUCCESS != err) {
			printf("clReleaseMemObject failed. Error: %d\n", err);
		}
		err = clReleaseMemObject(ctx[i].d_seed);
		if (CL_SUCCESS != err) {
			printf("clReleaseMemObject failed. Error: %d\n", err);
		}
		err = clReleaseMemObject(ctx[i].d_input);
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
		err = clReleaseKernel(ctx[i].k_peach);
		if (CL_SUCCESS != err) {
			printf("clReleaseKernel failed. Error: %d\n", err);
		}
		err = clReleaseContext(ctx[i].context);
		if (CL_SUCCESS != err) {
			printf("clReleaseContext failed. Error: %d\n", err);
		}
	}
}


int32_t peach_generate_cl(byte *bt, uint32_t *hps) {
	cl_int err;
	cl_uint i;
	uint64_t lastnHaiku = 0, nHaiku = 0;
	time_t seconds = time(NULL);

	for (i = 0; i < num_devices; i++) {
		/* Prepare next seed for GPU... */
		if (ctx[i].next_seed[0] == 0) {
			/* ... generate first GPU seed (and expand as Haiku) */
			trigg_gen(ctx[i].next_seed);

			/* ... and prepare round data */
			memcpy(ctx[i].input, bt, 92);
			memcpy(ctx[i].input + 92, ctx[i].next_seed, 16);
		}

		cl_int status = -1;
		if (ctx[i].trigg_event != NULL) {
			err = clGetEventInfo(ctx[i].trigg_event, CL_EVENT_COMMAND_EXECUTION_STATUS, sizeof(cl_int), &status, NULL);
			if (CL_SUCCESS != err) {
				printf("clGetEventInfo failed. Error: %d\n", err);
			}
		}
		else if (ctx[i].trigg_event == NULL) {
			status = CL_COMPLETE;
		}
		if (status == CL_COMPLETE) {
			// Calculate per GPU HPS
			ctx[i].t_end = timestamp_ms();
			double tdiff = (ctx[i].t_end - ctx[i].t_start) / 1000.0;
			ctx[i].hps_index = (ctx[i].hps_index + 1) % 3;
			ctx[i].hps[ctx[i].hps_index] = (uint32_t)(threads / tdiff);
			uint32_t shps = 0;
			for (int j = 0; j < 3; j++) {
				shps += ctx[i].hps[j];
			}
			ctx[i].ahps = shps / 3;
			// End per GPU HPS

			err = clEnqueueReadBuffer(ctx[i].cq, ctx[i].d_found, CL_TRUE, 0, 4, ctx[i].found, 0, NULL, NULL);
			if (CL_SUCCESS != err) {
				printf("%s:%d: clEnqueueReadBuffer failed. Error: %d\n", __FILE__, __LINE__, err);
			}

			if (*ctx[i].found == 1) { /* SOLVED A BLOCK! */
				err = clEnqueueReadBuffer(ctx[i].cq, ctx[i].d_seed, CL_TRUE, 0, 16, ctx[i].seed, 0, NULL, NULL);
				if (CL_SUCCESS != err) {
					printf("%s:%d: clEnqueueReadBuffer failed. Error: %d\n", __FILE__, __LINE__, err);
				}

				memcpy(bt + 92, ctx[i].curr_seed, 16);
				memcpy(bt + 92 + 16, ctx[i].seed, 16);
				return 1;
			}

			/* Send new GPU round data */
			//printf("input: "); for (int x = 0; x < 108; printf("%02x ", ctx[i].input[x]), x++); printf("\n");
			err = clEnqueueWriteBuffer(ctx[i].cq, ctx[i].d_input, CL_TRUE, 0, 108, ctx[i].input, 0, NULL, NULL);
			if (CL_SUCCESS != err) {
				printf("%s:%d: clEnqueueWriteBuffer failed. Error: %d\n", __FILE__, __LINE__, err);
			}
			ctx[i].t_start = timestamp_ms();

			err = clEnqueueNDRangeKernel(ctx[i].cq, ctx[i].k_peach, 1, NULL, &threads, &block, 0, NULL, &ctx[i].trigg_event);
			if (CL_SUCCESS != err) {
				printf("%s:%d: clEnqueueNDRangeKernel failed. Error: %d\n", __FILE__, __LINE__, err);
			}

			/* Add to haiku count */
			nHaiku += threads;

			/* Store round vars aside for checks next loop */
			memcpy(ctx[i].curr_seed, ctx[i].next_seed, 16);

			ctx[i].next_seed[0] = 0;
		}
	}

	/* Chill a bit if nothing is happening */
	if (lastnHaiku == nHaiku) msleep(1);
	else lastnHaiku = nHaiku;


	seconds = time(NULL) - seconds;
	if (seconds == 0) seconds = 1;
	nHaiku /= seconds;
	*hps = (uint32_t)nHaiku;

	return 0;

}

uint32_t cl_get_ahps(uint32_t device) {
	return ctx[device].ahps;
}