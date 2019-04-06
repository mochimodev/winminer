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

int trigg_init_gpu(byte difficulty, byte *blockNumber, Compute_Type ct) {
	switch (ct) {
	case CT_CUDA:
		return trigg_init_cuda(difficulty, blockNumber);
	case CT_OPENCL:
		return trigg_init_cl(difficulty, blockNumber);
	default:
		printf("Unknown compute type\n");
		return 0;
	}
}

char *trigg_generate_gpu(byte *mroot, uint32_t *nHaiku, Compute_Type ct) {
	switch (ct) {
	case CT_CUDA:
		return trigg_generate_cuda(mroot, nHaiku);
		break;
	case CT_OPENCL:
		return trigg_generate_cl(mroot, nHaiku);
		break;
	default:
		printf("Unknown compute type\n");
		return NULL;
	}
}

void trigg_free_gpu(Compute_Type ct) {
	switch (ct) {
	case CT_CUDA:
		trigg_free_cuda();
		break;
	case CT_OPENCL:
		trigg_free_cl();
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

Compute_Type autoselect_compute_type() {
	int cuda_devices = count_devices(CT_CUDA);
	int cl_devices = count_devices(CT_OPENCL);

	if (cl_devices > cuda_devices) {
		printf("Selecting compute type OpenCL\n");
		return CT_OPENCL;
	}
	printf("Selecting compute type CUDA\n");
	return CT_CUDA;
}