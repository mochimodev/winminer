/* trigg_cl.h  Header for OpenCL implementation of Trigg's Algorithm
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

/* GPU Prototypes */
int trigg_init_cl(byte difficulty, byte *blockNumber);
void trigg_free_cl();
char *trigg_generate_cl(byte *mroot, uint32_t *nHaiku);
int count_devices_cl();