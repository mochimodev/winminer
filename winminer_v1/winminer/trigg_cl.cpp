/* trigg_cl.cpp  OpenCL implementation of Trigg's Algorithm
 *
 * Copyright (c) 2019 by Adequate Systems, LLC.  All Rights Reserved.
 * See LICENSE.PDF   **** NO WARRANTY ****
 * https://github.com/mochimodev/mochimo/raw/master/LICENSE.PDF
 *
 * Date: 07 April 2019
 *
*/

#include "winminer.h"

#include "CL/cl.h"

int count_devices_cl() {
	cl_int err;
	cl_uint num_platforms, num_devices;

	cl_platform_id platform_id = NULL;
	cl_device_id device_id[10];

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


int trigg_init_cl(byte difficulty, byte *blockNumber) {
	return 0;
}

void trigg_free_cl() {

}
char *trigg_generate_cl(byte *mroot, uint32_t *nHaiku) {
	return NULL;
}