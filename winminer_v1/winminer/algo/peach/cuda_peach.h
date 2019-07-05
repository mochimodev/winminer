#pragma once
#include <stdint.h>
#include "../../types.h"

extern "C" {
	int init_cuda_peach(byte difficulty, byte *prevhash, byte *blocknumber);
	void free_cuda_peach();
	void cuda_peach(byte *bt, uint32_t *hps, byte *runflag);
	int32_t cuda_peach2(byte *bt, uint32_t *hps);

	typedef struct __peach_cuda_ctx {
		byte init, curr_seed[16], next_seed[16];
		byte *seed, *d_seed;
		byte *input, *d_map;
		int32_t *d_found;
		cudaStream_t stream;
		int64_t t_start, t_end;
		uint32_t hps[3];
		uint8_t hps_index;
		uint32_t ahps;
	} PeachCudaCTX;

	extern PeachCudaCTX peach_ctx[64];
}