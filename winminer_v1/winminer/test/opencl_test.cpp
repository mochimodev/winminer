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
	uint8_t curr_seed[16], next_seed[16];
	char cp[256], *next_cp;
	int *found;
	cl_mem d_map;
	cl_mem d_phash;
	cl_mem d_found;
	uint8_t *seed;
	cl_mem d_seed;
	uint32_t *midstate, *input;
	cl_mem d_midstate256, d_input32, d_blockNumber8;
	cl_context context;
	cl_command_queue cq;
	cl_kernel k_peach;
	cl_kernel k_peach_build;
	cl_event trigg_event;
} TriggCLCTX;

/* Max 64 GPUs Supported */
static TriggCLCTX ctx[64] = {};
//static int thrds = 3;
//static size_t threads = thrds * 1024 * 1024;
static size_t threads = 512*256;
static size_t block = 256;
//static size_t block = 1;
//static size_t threads = 128;
//static size_t block = 128;

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

	if (num_devices > 1) num_devices = 1;
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

		cl_program prog_md5 = opencl_compile_source(ctx[i].context, 1, &device_id[i], "../crypto/hash/opencl/cl_md5.cl", "-cl-fp32-correctly-rounded-divide-sqrt");
		cl_program prog_sha1 = opencl_compile_source(ctx[i].context, 1, &device_id[i], "../crypto/hash/opencl/cl_sha1.cl", "-cl-fp32-correctly-rounded-divide-sqrt");
		cl_program prog_sha256 = opencl_compile_source(ctx[i].context, 1, &device_id[i], "../crypto/hash/opencl/cl_sha256.cl", "-cl-fp32-correctly-rounded-divide-sqrt");
		cl_program prog_md2 = opencl_compile_source(ctx[i].context, 1, &device_id[i], "../crypto/hash/opencl/cl_md2.cl", "-cl-fp32-correctly-rounded-divide-sqrt");
		cl_program prog_keccak = opencl_compile_source(ctx[i].context, 1, &device_id[i], "../crypto/hash/opencl/cl_keccak.cl", "-cl-fp32-correctly-rounded-divide-sqrt");
		cl_program prog_blake2b = opencl_compile_source(ctx[i].context, 1, &device_id[i], "../crypto/hash/opencl/cl_blake2b.cl", "-cl-fp32-correctly-rounded-divide-sqrt");
		cl_program prog_peach = opencl_compile_source(ctx[i].context, 1, &device_id[i], "../algo/peach/cl_peach.cl", "-cl-fp32-correctly-rounded-divide-sqrt -O0 ");
		cl_program prog_parts[] = {prog_peach, prog_md5, prog_sha1, prog_sha256, prog_md2, prog_keccak, prog_blake2b};
		cl_program prog = clLinkProgram(ctx[i].context, 1, &device_id[i], NULL, 7, prog_parts, NULL, NULL, &err);
		if (CL_SUCCESS != err) {
			printf("clLinkProgram failed. Error: %d\n", err);
			exit(1);
		}

		ctx[i].k_peach_build = clCreateKernel(prog, "cl_build_map", &err);
		if (CL_SUCCESS != err) {
			printf("clCreateKernel failed. Error: %d\n", err);
			exit(1);
		}

		ctx[i].k_peach = clCreateKernel(prog, "cl_find_peach", &err);
		if (CL_SUCCESS != err) {
			printf("clCreateKernel failed. Error: %d\n", err);
		}

		/* Allocate device memory */
		ctx[i].d_map = clCreateBuffer(ctx[i].context, CL_MEM_READ_WRITE, MAP_LENGTH, NULL, &err);
		if (CL_SUCCESS != err) {
			printf("clCreateBuffer failed. Error: %d\n", err);
		}
		err = clEnqueueFillBuffer(ctx[i].cq, ctx[i].d_map, "\0", 1, 0, MAP_LENGTH, 0, NULL, NULL);
		if (CL_SUCCESS != err) {
			printf("clEnqueueFillBuffer failed. Error: %d\n", err);
		}

		ctx[i].d_phash = clCreateBuffer(ctx[i].context, CL_MEM_READ_ONLY, 32, NULL, &err);
		if (CL_SUCCESS != err) {
			printf("clCreateBuffer failed. Error: %d\n", err);
		}
		err = clEnqueueFillBuffer(ctx[i].cq, ctx[i].d_phash, "\0", 1, 0, 32, 0, NULL, NULL);
		if (CL_SUCCESS != err) {
			printf("clEnqueueFillBuffer failed. Error: %d\n", err);
		}

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
		clGetDeviceInfo(device_id[i], CL_DEVICE_LOCAL_MEM_SIZE, sizeof(cl_ulong), &size, 0);
		printf("CL_DEVICE_LOCAL_MEM_SIZE: %ld\n", size);
		printf("Running build_map\n");
		//size_t build_map_work_size = 4096*256;
		size_t build_map_work_size = 4096;
		size_t build_map_local_size = 256;
		//size_t build_map_work_size = 1;
		//size_t build_map_local_size = 1;
		for (int z = 0; z < 256; z++) {
			uint32_t start_index = z*4096;
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
		uint8_t map[1024];
		err = clEnqueueReadBuffer(ctx[i].cq, ctx[i].d_map, CL_TRUE, 0, 1024, map, 0, NULL, NULL);
		if (CL_SUCCESS != err) {
			printf("%s:%d: clEnqueueReadBuffer failed. Error: %d\n", __FILE__, __LINE__, err);
		}
		printf("map: ");
		for (int j = 0; j < 1024; j++) {
			printf("%02x ", map[j]);
		}
		printf("\n");

		uint8_t *full_map = (uint8_t*)malloc(MAP_LENGTH);
		err = clEnqueueReadBuffer(ctx[i].cq, ctx[i].d_map, CL_TRUE, 0, MAP_LENGTH, full_map, 0, NULL, NULL);
		if (CL_SUCCESS != err) {
			printf("%s:%d: clEnqueueReadBuffer failed. Error: %d\n", __FILE__, __LINE__, err);
		}
		FILE *fp = fopen("map.dat", "wb");
		//fwrite(full_map, 1, (size_t)MAP_LENGTH, fp);
		fwrite(full_map, 1, (size_t)(1*1024*1024), fp);
		fclose(fp);
		free(full_map);

		printf("1MB xxxfull map dumped\n");


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
		ctx[i].d_input32 = clCreateBuffer(ctx[i].context, CL_MEM_READ_ONLY, 108, NULL, &err);
		if (CL_SUCCESS != err) {
			printf("clCreateBuffer failed. Error: %d\n", err);
		}
		ctx[i].d_blockNumber8 = clCreateBuffer(ctx[i].context, CL_MEM_READ_ONLY, 8, NULL, &err);
		if (CL_SUCCESS != err) {
			printf("clCreateBuffer failed. Error: %d\n", err);
		}

		err = clEnqueueWriteBuffer(ctx[i].cq, ctx[i].d_blockNumber8, CL_FALSE, 0, 8, blockNumber, 0, NULL, NULL);
		if (CL_SUCCESS != err) {
			printf("%s:%d: clEnqueueWriteBuffer failed. Error: %d\n", __FILE__, __LINE__, err);
		}

		uint32_t max_threads = 131072;
		err = clSetKernelArg(ctx[i].k_peach, 0, 4, &max_threads);
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
		err = clSetKernelArg(ctx[i].k_peach, 4, sizeof(cl_mem), &ctx[i].d_input32);
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
		err = clEnqueueFillBuffer(ctx[i].cq, ctx[i].d_input32, "\0", 1, 0, 108, 0, NULL, NULL);
		if (CL_SUCCESS != err) {
			printf("clEnqueueFillBuffer failed. Error: %d\n", err);
		}
		/* Setup variables for "first round" */
		*ctx[i].found = 0;
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

	for (uint32_t i = 0; i < num_devices; i++) {
		cl_int err;


#if 0
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
#endif

		clReleaseMemObject(ctx[i].d_map);
		clReleaseMemObject(ctx[i].d_phash);
	}
}

