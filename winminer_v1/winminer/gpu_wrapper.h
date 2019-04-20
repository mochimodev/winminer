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
#include "trigg_cuda.h"
#include "trigg_cl.h"

enum Compute_Type { CT_CUDA, CT_OPENCL };

/* GPU Prototypes */
int trigg_init_gpu(byte difficulty, byte *blockNumber, Compute_Type ct);
void trigg_free_gpu(Compute_Type ct);
char *trigg_generate_gpu(byte *mroot, uint32_t *nHaiku, Compute_Type ct);
Compute_Type autoselect_compute_type();