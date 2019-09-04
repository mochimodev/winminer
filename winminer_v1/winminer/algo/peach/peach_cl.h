/* peach_cl.h  Header for OpenCL implementation of peach algorithm
 *
 * Copyright (c) 2019 by Adequate Systems, LLC.  All Rights Reserved.
 * See LICENSE.PDF   **** NO WARRANTY ****
 * https://github.com/mochimodev/mochimo/raw/master/LICENSE.PDF
 *
 * Date: 02 September 2019
 *
*/

#pragma once

#include "../../types.h"
#include <stdint.h>

/* GPU Prototypes */
int peach_init_cl(byte difficulty, byte *prevhash, byte *blocknumber);
void peach_free_cl();
int32_t peach_generate_cl(byte *bt, uint32_t *hps);
int count_devices_cl();
uint32_t cl_get_ahps(uint32_t device);