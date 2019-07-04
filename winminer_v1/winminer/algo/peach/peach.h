/*
 * peach.h  FPGA-Tough CPU Mining Algo Definitions
 *
 * Copyright (c) 2019 by Adequate Systems, LLC.  All Rights Reserved.
 * See LICENSE.PDF   **** NO WARRANTY ****
 *
 * Date: 05 June 2019
 * Revision: 1
 *
 * This file is subject to the license as found in LICENSE.PDF
 *
 */

#include "../../types.h"

#define HASHLENMID 	                   16
#define HASHLEN                        32
#define TILE_ROWS                      32
#define TILE_LENGTH (TILE_ROWS * HASHLEN)
#define TILE_TRANSFORMS                 8
#define MAP                       1048576
#define MAP_LENGTH    (TILE_LENGTH * MAP)
#define JUMP                            8

#define PEACH_DEBUG                     0

#ifdef __cplusplus
extern "C" {
#endif

	int peach(BTRAILER *bt, word32 difficulty, word32 *hps, int mode);

#ifdef __cplusplus
}
#endif