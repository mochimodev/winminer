/* gpu_wrapper.cpp  Implementation for GPU wrapper
 *
 * Copyright (c) 2019 by Adequate Systems, LLC.  All Rights Reserved.
 * See LICENSE.PDF   **** NO WARRANTY ****
 * https://github.com/mochimodev/mochimo/raw/master/LICENSE.PDF
 *
 * Date: 07 April 2019
 *
*/

#include "gpu_wrapper.h"
#include "miner.h"
#include <stdio.h>

int peach_init_gpu(byte difficulty, byte *prevhash, byte *blockNumber, Compute_Type ct) {
	switch (ct) {
	case CT_CUDA:
		return init_cuda_peach(difficulty, prevhash, blockNumber);
	case CT_OPENCL:
		return peach_init_cl(difficulty, prevhash, blockNumber);
	default:
		printf("Unknown compute type\n");
		return 0;
	}
}

int32_t peach_generate_gpu(byte *bt, uint32_t *hps, Compute_Type ct) {
	switch (ct) {
	case CT_CUDA:
		return cuda_peach2(bt, hps);
		break;
	case CT_OPENCL:
		return peach_generate_cl(bt, hps);
		break;
	default:
		printf("Unknown compute type\n");
		return NULL;
	}
}

void peach_free_gpu(Compute_Type ct) {
	switch (ct) {
	case CT_CUDA:
		free_cuda_peach();
		break;
	case CT_OPENCL:
		//peach_free_cl();
		break;
	default:
		printf("Unknown compute type\n");
		return;
	}
}

int count_devices(Compute_Type ct) {
	switch (ct) {
	case CT_CUDA:
		return count_devices_cuda();
		break;
	case CT_OPENCL:
		return count_devices_cl();
		break;
	default:
		printf("Unknown compute type\n");
		return CT_CUDA;
	}
}

uint32_t gpu_get_ahps(uint32_t device, Compute_Type ct) {
	switch (ct) {
	case CT_CUDA:
		return cuda_get_ahps(device);
		break;
	case CT_OPENCL:
		return cl_get_ahps(device);
		break;
	default:
		printf("Unknown compute type\n");
		return CT_CUDA;
	}
}

Compute_Type autoselect_compute_type() {
	int cuda_devices = count_devices(CT_CUDA);
	int cl_devices = count_devices(CT_OPENCL);

	num_cuda = cuda_devices;
	num_opencl = cl_devices;

	if (cl_devices > cuda_devices) {
		printf("Selecting compute type OpenCL\n");
		num_cuda = 0;
		return CT_OPENCL;
	}
	printf("Selecting compute type CUDA\n");
	num_opencl = 0;
	return CT_CUDA;
}