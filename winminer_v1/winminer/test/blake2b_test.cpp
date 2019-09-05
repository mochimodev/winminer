#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>
#include <sys/time.h>
#define CL_TARGET_OPENCL_VERSION 120
#define CL_USE_DEPRECATED_OPENCL_1_2_APIS
#define __CL_ENABLE_EXCEPTIONS
#include <CL/cl.h>

#pragma comment(lib, "OpenCL.lib")

#define HASHLENMID 	                   16
#define HASHLEN                        32
#define TILE_ROWS                      32
#define TILE_LENGTH (TILE_ROWS * HASHLEN)
#define TILE_TRANSFORMS                 8
#define MAP                       1048576
#define MAP_LENGTH    (TILE_LENGTH * MAP)
#define JUMP                            8

cl_uint num_devices = 0;
cl_platform_id platform_id = NULL;
cl_device_id device_id[10];


typedef struct __trigg_opencl_ctx {
	cl_mem d_in;
	cl_mem d_out;
	cl_context context;
	cl_command_queue cq;
	cl_kernel k_blake2b;
	cl_event trigg_event;
} TriggCLCTX;

/* Max 64 GPUs Supported */
static TriggCLCTX ctx[64] = {};
//static int thrds = 3;
//static size_t threads = thrds * 1024 * 1024;
//static size_t threads = 512*256;
//static size_t block = 256;
static size_t threads = 2;
static size_t block = 1;

cl_program opencl_compile_source(cl_context context, uint8_t num_devices, cl_device_id *devices, const char *filename, const char *options) {
	printf("Compiling: %s\n", filename);
	/*HRSRC rsc = FindResource(NULL, MAKEINTRESOURCE(IDR_OPENCL_SOURCE1), _T("OPENCL_SOURCE"));
	if (rsc == NULL) {
		DWORD dwErr = GetLastError();
		printf("FindResource failed. Error: %lu\n", dwErr);
	}
	HGLOBAL resGlobal = LoadResource(NULL, rsc);
	char *src = (char*)LockResource(resGlobal);
	DWORD dwSize = SizeofResource(NULL, rsc);*/
	FILE *fp = fopen(filename, "r");
	if (!fp) {
		fprintf(stderr, "Failed to load kernel.\n");
		exit(1);
	}
	char *src = (char*)malloc(102400);
	size_t dwSize = fread( src, 1, 102400, fp);
	fclose( fp );

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

	free(src);

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

int trigg_init_cl(uint8_t  difficulty, uint8_t *blockNumber) {
	count_devices_cl();
	cl_context_properties properties[] = { CL_CONTEXT_PLATFORM, (cl_context_properties)platform_id, 0 };

	for (cl_uint i = 0; i < num_devices; i++) {
		cl_int err;
		ctx[i].context = clCreateContext(properties, 1, &(device_id[i]), NULL, NULL, &err);
		if (CL_SUCCESS != err) {
			printf("clCreateContext failed. Error: %d\n", err);
			exit(1);
		}
		ctx[i].cq = clCreateCommandQueue(ctx[i].context, device_id[i], 0, &err);
		if (CL_SUCCESS != err) {
			printf("clCreateCommandQueue failed. Error: %d\n", err);
			exit(1);
		}

		cl_program prog_blake2b = opencl_compile_source(ctx[i].context, 1, &device_id[i], "../crypto/hash/opencl/cl_blake2b.cl", "-cl-fp32-correctly-rounded-divide-sqrt");
		cl_program prog_parts[] = {prog_blake2b};
		cl_program prog = clLinkProgram(ctx[i].context, 1, &device_id[i], NULL, 1, prog_parts, NULL, NULL, &err);
		if (CL_SUCCESS != err) {
			printf("clLinkProgram failed. Error: %d\n", err);
			exit(1);
		}

		ctx[i].k_blake2b = clCreateKernel(prog, "test_blake2b", &err);
		if (CL_SUCCESS != err) {
			printf("clCreateKernel failed. Error: %d\n", err);
			exit(1);
		}

		/* Allocate device memory */
		ctx[i].d_in = clCreateBuffer(ctx[i].context, CL_MEM_READ_WRITE, 32, NULL, &err);
		if (CL_SUCCESS != err) {
			printf("clCreateBuffer failed. Error: %d\n", err);
		}
		uint8_t input[32] = {0x70, 0x5b, 0xa6, 0xa5, 0x84, 0x69, 0x3f, 0x79, 0x53, 0x65, 0x2d, 0xb6, 0xfb, 0xf8, 0x25, 0xe6, 0x85, 0x9a, 0xa7, 0x09, 0xda, 0x9a, 0x70, 0x47, 0xfa, 0x14, 0xa0, 0xd1, 0x13, 0x36, 0xcb, 0x59};
		err = clEnqueueWriteBuffer(ctx[i].cq, ctx[i].d_in, CL_TRUE, 0, 32, input, 0, NULL, NULL);
		if (CL_SUCCESS != err) {
			printf("%s:%d: clEnqueueFillBuffer failed. Error: %d\n", __FILE__, __LINE__, err);
		}

#define NUM_HASHES 8192*1024
		ctx[i].d_out = clCreateBuffer(ctx[i].context, CL_MEM_READ_WRITE, 32*NUM_HASHES, NULL, &err);
		if (CL_SUCCESS != err) {
			printf("clCreateBuffer failed. Error: %d\n", err);
		}
		err = clEnqueueFillBuffer(ctx[i].cq, ctx[i].d_out, "\0", 1, 0, 32*NUM_HASHES, 0, NULL, NULL);
		if (CL_SUCCESS != err) {
			printf("%s:%d: clEnqueueFillBuffer failed. Error: %d\n", __FILE__, __LINE__, err);
		}


		err = clSetKernelArg(ctx[i].k_blake2b, 0, sizeof(cl_mem), &ctx[i].d_in);
		if (CL_SUCCESS != err) {
			printf("%s:%d: clSetKernelArg failed. Error: %d\n", __FILE__, __LINE__, err);
		}
		err = clSetKernelArg(ctx[i].k_blake2b, 1, sizeof(cl_mem), &ctx[i].d_out);
		if (CL_SUCCESS != err) {
			printf("%s:%d: clSetKernelArg failed. Error: %d\n", __FILE__, __LINE__, err);
		}
		err = clFinish(ctx[i].cq);
		if (CL_SUCCESS != err) {
			printf("clFinish failed. Error: %d\n", err);
		}

		cl_ulong size;
		clGetDeviceInfo(device_id[i], CL_DEVICE_LOCAL_MEM_SIZE, sizeof(cl_ulong), &size, 0);
		printf("CL_DEVICE_LOCAL_MEM_SIZE: %ld\n", size);
		printf("Running blake2b\n");
		size_t blake2b_work_size = NUM_HASHES;
		size_t blake2b_local_size = 256;
		for (int z = 0; z < 1; z++) {
			uint32_t start_index = z*4096;
			err = clEnqueueNDRangeKernel(ctx[i].cq, ctx[i].k_blake2b, 1, NULL, &blake2b_work_size, &blake2b_local_size, 0, NULL, &ctx[i].trigg_event);
			if (CL_SUCCESS != err) {
				printf("%s:%d: clEnqueueNDRangeKernel failed. Error: %d\n", __FILE__, __LINE__, err);
			}
		}
		err = clFinish(ctx[i].cq);
		if (CL_SUCCESS != err) {
			printf("clFinish failed. Error: %d\n", err);
		}
		printf("Blake2b complete\n");
		uint8_t map[1024];
		err = clEnqueueReadBuffer(ctx[i].cq, ctx[i].d_out, CL_TRUE, 0, 1024, map, 0, NULL, NULL);
		if (CL_SUCCESS != err) {
			printf("%s:%d: clEnqueueReadBuffer failed. Error: %d\n", __FILE__, __LINE__, err);
		}

		printf("map: ");
		for (int j = 0; j < 1024; j++) {
			if (j % 32 == 0) printf("\n");
			printf("%02x ", map[j]);
		}
		printf("\n");

		uint8_t *full_map = (uint8_t*)malloc(MAP_LENGTH);
		err = clEnqueueReadBuffer(ctx[i].cq, ctx[i].d_out, CL_TRUE, 0, 32*NUM_HASHES, full_map, 0, NULL, NULL);
		if (CL_SUCCESS != err) {
			printf("%s:%d: clEnqueueReadBuffer failed. Error: %d\n", __FILE__, __LINE__, err);
		}
		FILE *fp = fopen("blake2b.dat", "wb");
		fwrite(full_map, 1, (size_t)(32*NUM_HASHES), fp);
		fclose(fp);
		free(full_map);

		clReleaseMemObject(ctx[i].d_in);
		clReleaseMemObject(ctx[i].d_out);


		/* Setup variables for "first round" */
		printf("\nTrace: GPU %d Initialized.", i);
	}

	return num_devices;
}

int main() {
	uint64_t blockNumber = 1;
	uint8_t *bnum = (uint8_t*)&blockNumber;
	uint8_t diff = 18;
	trigg_init_cl(diff, bnum);
	struct timeval t_start, t_end;

#if 0
	for (uint32_t i = 0; i < num_devices; i++) {
		cl_int err;


            	gettimeofday(&t_start, NULL);
		err = clSetKernelArg(ctx[i].k_peach, 5, 1, &diff);
		if (CL_SUCCESS != err) {
			printf("%s:%d: clSetKernelArg failed. Error: %d\n", __FILE__, __LINE__, err);
		}

		err = clEnqueueNDRangeKernel(ctx[i].cq, ctx[i].k_peach, 1, NULL, &threads, &block, 0, NULL, &ctx[i].trigg_event);
		if (CL_SUCCESS != err) {
			printf("%s:%d: clEnqueueNDRangeKernel failed. Error: %d\n", __FILE__, __LINE__, err);
		}

		printf("Waiting for completion on GPU: %d\n", i);
		err = clFinish(ctx[i].cq);
		if (CL_SUCCESS != err) {
			printf("clFinish failed. Error: %d\n", err);
		}

            	gettimeofday(&t_end, NULL);
            	uint64_t ustart = 1000000 * t_start.tv_sec + t_start.tv_usec;
               uint64_t uend = 1000000 * t_end.tv_sec + t_end.tv_usec;
               double tdiff = (uend - ustart) / 1000.0 / 1000.0;
	       printf("Diff: %f seconds\n", tdiff);
	       printf("Hashrate: %f\n", threads / tdiff);

		err = clEnqueueReadBuffer(ctx[i].cq, ctx[i].d_found, CL_TRUE, 0, 4, ctx[i].found, 0, NULL, NULL);
		if (CL_SUCCESS != err) {
			printf("%s:%d: clEnqueueReadBuffer failed. Error: %d\n", __FILE__, __LINE__, err);
		}
		printf("Found?: %d\n", *ctx[i].found);

		err = clEnqueueReadBuffer(ctx[i].cq, ctx[i].d_seed, CL_TRUE, 0, 16, ctx[i].seed, 0, NULL, NULL);
		if (CL_SUCCESS != err) {
			printf("%s:%d: clEnqueueReadBuffer failed. Error: %d\n", __FILE__, __LINE__, err);
		}
		printf("Seed: ");
		for (int j = 0; j < 16; j++) {
			printf("%02x ", ctx[i].seed[j]);
		}
		printf("\n");

		err = clEnqueueNDRangeKernel(ctx[i].cq, ctx[i].k_peach, 1, NULL, &threads, &block, 0, NULL, &ctx[i].trigg_event);
		if (CL_SUCCESS != err) {
			printf("%s:%d: clEnqueueNDRangeKernel failed. Error: %d\n", __FILE__, __LINE__, err);
		}

		printf("Waiting for completion on GPU: %d\n", i);
		err = clFinish(ctx[i].cq);
		if (CL_SUCCESS != err) {
			printf("clFinish failed. Error: %d\n", err);
		}

		err = clEnqueueReadBuffer(ctx[i].cq, ctx[i].d_found, CL_TRUE, 0, 4, ctx[i].found, 0, NULL, NULL);
		if (CL_SUCCESS != err) {
			printf("%s:%d: clEnqueueReadBuffer failed. Error: %d\n", __FILE__, __LINE__, err);
		}
		printf("Found?: %d\n", *ctx[i].found);

		err = clEnqueueReadBuffer(ctx[i].cq, ctx[i].d_seed, CL_TRUE, 0, 16, ctx[i].seed, 0, NULL, NULL);
		if (CL_SUCCESS != err) {
			printf("%s:%d: clEnqueueReadBuffer failed. Error: %d\n", __FILE__, __LINE__, err);
		}
		printf("Seed: ");
		for (int j = 0; j < 16; j++) {
			printf("%02x ", ctx[i].seed[j]);
		}
		printf("\n");

		clReleaseMemObject(ctx[i].d_map);
		clReleaseMemObject(ctx[i].d_phash);
	}
#endif
}

