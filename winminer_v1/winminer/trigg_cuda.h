/* trigg_cuda.h  Header for CUDA implementation of Trigg's Algorithm
 *
 * Copyright (c) 2019 by Adequate Systems, LLC.  All Rights Reserved.
 * See LICENSE.PDF   **** NO WARRANTY ****
 * https://github.com/mochimodev/mochimo/raw/master/LICENSE.PDF
 *
 * Date: 07 April 2019
 *
*/

#pragma once

#include "helper_cuda.h"
#include <cuda_runtime.h>

#include "types.h"

/* GPU Prototypes */
__host__ int trigg_init_cuda(byte difficulty, byte *blockNumber);
__host__ void trigg_free_cuda();
__host__ char *trigg_generate_cuda(byte *mroot, uint32_t *nHaiku);
__host__ int count_devices_cuda();