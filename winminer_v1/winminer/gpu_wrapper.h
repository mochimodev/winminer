/* gpu_wrapper.h  Header for GPU wrapper
 *
 * Copyright (c) 2019 by Adequate Systems, LLC.  All Rights Reserved.
 * See LICENSE.PDF   **** NO WARRANTY ****
 * https://github.com/mochimodev/mochimo/raw/master/LICENSE.PDF
 *
 * Date: 07 April 2019
 *
*/

#pragma once

#include "types.h"
#include "algo/peach/cuda_peach.h"
#include "algo/peach/peach_cl.h"

enum Compute_Type { CT_CUDA, CT_OPENCL };

/* GPU Prototypes */
int peach_init_gpu(byte difficulty, byte *prevhash, byte *blockNumber, Compute_Type ct);
void peach_free_gpu(Compute_Type ct);
int32_t peach_generate_gpu(byte *bt, uint32_t *hps, Compute_Type ct);
Compute_Type autoselect_compute_type();
uint32_t gpu_get_ahps(uint32_t device, Compute_Type ct);