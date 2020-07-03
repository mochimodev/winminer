/*
 * cl_trigg.cu  Multi-GPU CUDA Mining
 *
 * Copyright (c) 2019 by Adequate Systems, LLC.  All Rights Reserved.
 * See LICENSE.PDF   **** NO WARRANTY ****
 *
 * Date: 10 August 2018
 * Revision: 31
 */

#pragma OPENCL EXTENSION cl_khr_byte_addressable_store : enable

#define AMD

#define __CL_ENABLE_EXCEPTIONS
//#pragma OPENCL EXTENSION cl_khr_int64_base_atomics : enable
typedef uchar uint8_t;
typedef int int32_t;
typedef uint uint32_t;
typedef long int64_t;
typedef ulong uint64_t;
typedef uchar BYTE;             // 8-bit byte
typedef uint  WORD;             // 32-bit word, change to "long" for 16-bit machines
typedef ulong LONG;
#define __forceinline__ inline
#define memcpy(dst,src,size); { for (int mi = 0; mi < size; mi++) { ((uint8_t*)dst)[mi] = ((uint8_t*)src)[mi]; } }
#define printf16(head, var); printf(head \
					 "%02x %02x %02x %02x " \
					 "%02x %02x %02x %02x " \
					 "%02x %02x %02x %02x " \
					 "%02x %02x %02x %02x\n", \
					 var[0], var[1], var[2], var[3], \
					 var[4], var[5], var[6], var[7], \
					 var[8], var[9], var[10], var[11], \
					 var[12], var[13], var[14], var[15]);
#define printf32(head, var); printf(head \
					 "%02x %02x %02x %02x " \
					 "%02x %02x %02x %02x " \
					 "%02x %02x %02x %02x " \
					 "%02x %02x %02x %02x " \
					 "%02x %02x %02x %02x " \
					 "%02x %02x %02x %02x " \
					 "%02x %02x %02x %02x " \
					 "%02x %02x %02x %02x\n", \
					 var[0], var[1], var[2], var[3], \
					 var[4], var[5], var[6], var[7], \
					 var[8], var[9], var[10], var[11], \
					 var[12], var[13], var[14], var[15], \
					 var[16], var[17], var[18], var[19], \
					 var[20], var[21], var[22], var[23], \
					 var[24], var[25], var[26], var[27], \
					 var[28], var[29], var[30], var[31]);


#define HASHLENMID 	                   16
#define HASHLEN                        32
#define TILE_ROWS                      32
#define TILE_LENGTH (TILE_ROWS * HASHLEN)
#define TILE_TRANSFORMS                 8
#define MAP                       1048576
#define MAP_LENGTH    (TILE_LENGTH * MAP)
#define JUMP                            8

#define PEACH_DEBUG                     0

typedef struct {
	BYTE data[64];
	WORD datalen;
	unsigned long bitlen;
	WORD state[4];
} CUDA_MD5_CTX;

typedef struct {
	BYTE data[16];
	BYTE state[48];
	BYTE checksum[16];
	int len;
} CUDA_MD2_CTX;

typedef struct {

   uint32_t algo_type;

   union {
	   CUDA_MD2_CTX md2;
	   CUDA_MD5_CTX md5;
   };

} CUDA_NIGHTHASH_CTX;

uint8_t *trigg_gen(uint8_t *in);
void cl_nighthash_init_transform_32B(CUDA_NIGHTHASH_CTX *ctx, uint8_t *algo_type_seed, uint32_t index);
void cl_nighthash_init_transform_36B(CUDA_NIGHTHASH_CTX *ctx, uint8_t *algo_type_seed, uint32_t index);
void cl_nighthash_init_notransform_1060B(CUDA_NIGHTHASH_CTX *ctx, uint8_t *algo_type_seed, uint32_t index);
void cl_nighthash_update(CUDA_NIGHTHASH_CTX *ctx, uint8_t *in, uint32_t inlen);
void cl_nighthash_final(CUDA_NIGHTHASH_CTX *ctx, uint8_t *out);
void SHA2_256_36B(uint *Digest, const uint *InData);
void SHA2_256_124B(uint *Digest, const uint *InData);
void SHA2_256_1056B_1060B(uint *Digest, const uint *InData, bool Is1060);
void Blake2B_K32_36B(uchar *out, uchar *in);
void Blake2B_K64_36B(uchar *out, uchar *in);
void Blake2B_K32_1060B(uchar *out, uchar *in);
void Blake2B_K64_1060B(uchar *out, uchar *in);
void SHA1Digest36B(uint *Digest, const uint *Input);
void SHA1Digest1060B(uint *Digest, const uint *Input);
void Keccak256Digest36B(ulong *Digest, const ulong *Input);
void Keccak256Digest1060B(ulong *Digest, const ulong *Input);
void SHA3256Digest36B(ulong *Digest, const ulong *Input);
void SHA3Digest1060B(uint64_t *Digest, const uint64_t *Input);
void cl_md2_init(CUDA_MD2_CTX *ctx);
void cl_md2_update(CUDA_MD2_CTX *ctx, BYTE data[], size_t len);
void cl_md2_final(CUDA_MD2_CTX *ctx, BYTE hash[]);
void cl_md5_init(CUDA_MD5_CTX *ctx);
void cl_md5_update(CUDA_MD5_CTX *ctx, BYTE data[], size_t len);
void cl_md5_final(CUDA_MD5_CTX *ctx, BYTE hash[]);

__constant static int Z_MASS[4] = {238,239,240,242};
__constant static int Z_ING[2]  = {42,43};
__constant static int Z_TIME[16] =
   {82,83,84,85,86,87,88,243,249,250,251,252,253,254,255,253};
__constant static int Z_AMB[16] =
   {77,94,95,96,126,214,217,218,220,222,223,224,225,226,227,228};
__constant static int Z_ADJ[64] =
   {61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,
    88,89,90,91,92,94,95,96,97,98,99,100,101,102,103,104,105,107,108,109,110,112,114,
    115,116,117,118,119,120,121,122,123,124,125,126,127,128};

uint32_t cl_next_index(uint32_t index, __global uint8_t *g_map, uint8_t *nonce, uint8_t *scratch, uint8_t debug)
{
   CUDA_NIGHTHASH_CTX nighthash;

   //uint8_t seed[HASHLEN + 4 + TILE_LENGTH];
   uint8_t *seed = scratch;
   const int seedlen = HASHLEN + 4 + TILE_LENGTH;

   uint8_t hash[HASHLEN];
   int i = 0;

   /* Create nighthash seed for this index on the map */
    for (int i = 0; i < HASHLEN; i++) {
	    ((uint8_t*)seed)[i] = nonce[i];
    }
    for (int i = 0; i < 4; i++) {
	    ((uint8_t*)(seed+HASHLEN))[i] = ((uint8_t*)&index)[i];
    }
    for (int i = 0; i < TILE_LENGTH; i++) {
	    ((uint8_t*)(seed+HASHLEN+4))[i] = g_map[index*TILE_LENGTH + i];
    }

#ifdef DEBUG
   if (debug) {
	   printf32("first tile: ", (&g_map[index * TILE_LENGTH]));
	   printf32("cl_next_index seed: ", seed);
   }
#endif
   
   /* Setup nighthash the seed, NO TRANSFORM */
   cl_nighthash_init_notransform_1060B(&nighthash, seed, index);

   if (nighthash.algo_type == 0) {
	   Blake2B_K32_1060B((uchar*)hash, (uchar*)seed);
   } else if (nighthash.algo_type == 1) {
	   Blake2B_K64_1060B((uchar*)hash, (uchar*)seed);
   } else if (nighthash.algo_type == 2) {
	   SHA1Digest1060B((uint*)hash, (uint*)seed);
	   for (int i = 0; i < 12; i++) {
		   hash[20+i] = 0;
	   }
   } else if (nighthash.algo_type == 3) {
	   SHA2_256_1056B_1060B((uint*)hash, (uint*)seed, true);
   } else if (nighthash.algo_type == 4) {
	   SHA3Digest1060B((ulong*)hash, (ulong*)seed);
   } else if (nighthash.algo_type == 5) {
	   Keccak256Digest1060B((ulong*)hash, (ulong*)seed);
   } else {
	   /* Update nighthash with the seed data */
	   cl_nighthash_update(&nighthash, seed, seedlen);

	   /* Finalize nighthash into the first 32 byte chunk of the tile */
	   cl_nighthash_final(&nighthash, hash);
   }

   /* Convert 32-byte Hash Value Into 8x 32-bit Unsigned Integer */
   for(i = 0, index = 0; i < 8; i++) {
      index += ((uint32_t *) hash)[i];
   }

   return index % MAP;
}


void cl_gen_tile(uint32_t index, __global uint8_t *g_map, uint8_t debug, __global uint8_t *c_phash)
{
   CUDA_NIGHTHASH_CTX nighthash;
   uint8_t seed[4 + HASHLEN];
   global uint8_t *tilep;
   uint8_t local_out[4 + HASHLEN];
   int i, j, seedlen;

   /* Set map pointer */
   tilep = &g_map[index * TILE_LENGTH];

   /* Create nighthash seed for this index on the map */
   seedlen = 4 + HASHLEN;
    for (int i = 0; i < 4; i++) {
	    seed[i] = ((uint8_t*)&index)[i];
    }
    for (int i = 0; i < HASHLEN; i++) {
	    (seed+4)[i] = ((__global uint8_t*)c_phash)[i];
    }

   /* Setup nighthash with a transform of the seed */
   cl_nighthash_init_transform_36B(&nighthash, seed, index);

   if (nighthash.algo_type == 0) {
	   Blake2B_K32_36B((uchar*)local_out, (uchar*)seed);
   } else if (nighthash.algo_type == 1) {
	   Blake2B_K64_36B((uchar*)local_out, (uchar*)seed);
   } else if (nighthash.algo_type == 2) {
	   SHA1Digest36B((uint*)local_out, (uint*)seed);
	   for (int i = 0; i < 12; i++) {
		   local_out[20+i] = 0;
	   }
   } else if (nighthash.algo_type == 3) {
	   SHA2_256_36B((uint*)local_out, (uint*)seed);
   } else if (nighthash.algo_type == 4) {
   	SHA3256Digest36B((ulong*)local_out, (ulong*)seed);
   } else if (nighthash.algo_type == 5) {
   	Keccak256Digest36B((ulong*)local_out, (ulong*)seed);
   } else {

	   /* Update nighthash with the seed data */
	   cl_nighthash_update(&nighthash, seed, seedlen);

	   /* Finalize nighthash into the first 32 byte chunk of the tile */
	   cl_nighthash_final(&nighthash, local_out);
   }

   for (int i = 0; i < HASHLEN; i++) {
	   tilep[i] = local_out[i];
   }

   /* Begin constructing the full tile */
   for(i = 0, j = HASHLEN; j < TILE_LENGTH; i += HASHLEN, j += HASHLEN) { /* For each tile row */
	   /* Hash the current row to the next, if not at the end */
	   /* Setup nighthash with a transform of the current row */
	   cl_nighthash_init_transform_32B(&nighthash, local_out, index);
	   for (int z = 0; z < HASHLEN; z++) {
		   tilep[i+z] = local_out[z];
	   }
	   // Copy index to end of local_out
	   for (int z = 0; z < 4; z++) {
		   local_out[HASHLEN+z] = ((uint8_t*)&index)[z];
	   }

	   if (nighthash.algo_type == 0) {
		   Blake2B_K32_36B((uchar*)local_out, (uchar*)local_out);
	   } else if (nighthash.algo_type == 1) {
		   Blake2B_K64_36B((uchar*)local_out, (uchar*)local_out);
	   } else if (nighthash.algo_type == 2) {
		   SHA1Digest36B((uint*)local_out, (uint*)local_out);
		   for (int i = 0; i < 12; i++) {
			   local_out[20+i] = 0;
		   }
	   } else if (nighthash.algo_type == 3) {
		   SHA2_256_36B((uint*)local_out, (uint*)local_out);
	   } else if (nighthash.algo_type == 4) {
		   SHA3256Digest36B((ulong*)local_out, (ulong*)local_out);
	   } else if (nighthash.algo_type == 5) {
		   Keccak256Digest36B((ulong*)local_out, (ulong*)local_out);
	   } else {
		   /* Update nighthash with the seed data and tile index */
		   cl_nighthash_update(&nighthash, local_out, HASHLEN+4);
		   cl_nighthash_final(&nighthash, local_out);
	   }
	   for (int z = 0; z < HASHLEN; z++) {
		   tilep[j+z] = local_out[z];
	   }
   }
}


__kernel void cl_build_map(__global uint8_t *g_map, __global uint8_t *c_phash, uint32_t start_index)
{
   uint32_t thread = get_global_id(0) + start_index;
   if (thread < MAP) {
      cl_gen_tile(thread, g_map, /*thread == 32 ? 1 :*/ 0 , c_phash);
   }

   // Do NOT remove this.
   // Load-bearing lines of code.
   // Thread will never reach 1024*1024+1,
   // but the map will become wrong without this.
   if (thread == 1024*1024+1) {
	   CUDA_NIGHTHASH_CTX ctx;
	   printf("%p\n", &(ctx.md5));
   }
}


__kernel void cl_find_peach(uint32_t threads, __global uint8_t *g_map,
                                __global int32_t *g_found, __global uint8_t *g_seed, __global uint8_t *c_input, uint8_t c_difficulty)
{
   uint32_t thread = get_global_id(0);// + 122868 - 120;
   uint8_t scratch[1060]; // scratch space for cl_next_index

   uint8_t seed[16] = {0}, nonce[32] = {0};
   uint8_t bt_hash[32], fhash[32];
   int32_t i, j, n;
   uint8_t x;
   uint32_t sm;

   if (thread < threads) {
      /* Determine second seed */
      if(thread < 131072) { /* This frame permutations: 131,072 */
         seed[ 0] = Z_TIME[(thread & 15)];
         seed[ 1] = Z_AMB[(thread >> 4) & 15];
         seed[ 2] = 1;
         seed[ 3] = Z_ADJ[(thread >> 8) & 63];
         seed[ 4] = Z_MASS[(thread >> 14) & 3];
         seed[ 5] = 1;
         seed[ 6] = Z_ING[(thread >> 16) & 1];
      }

      /* store full nonce */
      #pragma unroll
      for (i = 0; i < 16; i++)
         nonce[i] = c_input[i + 92];

      #pragma unroll
      for (i = 0; i < 16; i++)
         nonce[i+16] = seed[i];

      /*********************************************************/
      /* Hash 124 bytes of Block Trailer, including both seeds */

      uint8_t l_input[124];
      for (int i = 0; i < 108; i++) {
	      l_input[i] = c_input[i];
      }
#pragma unroll
      for (int i = 0; i < 16; i++) {
	      l_input[108+i] = nonce[16+i];
      }
      SHA2_256_124B((uint*)bt_hash, (uint*)l_input);

      /****************************************************/
      /* Follow the tile path based on the selected nonce */
      
      sm = bt_hash[0];
      #pragma unroll
      for(i = 1; i < HASHLEN; i++) {
         sm *= bt_hash[i];
      }
      sm %= MAP;

uint32_t sm_chain[JUMP];
      /* make <JUMP> tile jumps to find the final tile */
      #pragma unroll
      for(j = 0; j < JUMP; j++) {
        sm = cl_next_index(sm, g_map, nonce, scratch, /*thread == 122868 ? 1 :*/ 0);
	sm_chain[j] = sm;
      }

      /****************************************************************/
      /* Check the hash of the final tile produces the desired result */

      uint8_t btbuf[HASHLEN+TILE_LENGTH];
#pragma unroll
      for (int i = 0; i < HASHLEN; i++) {
	      btbuf[i] = bt_hash[i];
      }
      for (int i = 0; i < TILE_LENGTH; i++) {
	      btbuf[HASHLEN+i] = g_map[sm*TILE_LENGTH + i];
      }
      SHA2_256_1056B_1060B((uint*)fhash, (uint*)btbuf, false);

      /* Evaluate hash */
      for (x = i = j = n = 0; i < HASHLEN; i++) {
         x = fhash[i];
         if (x != 0) {
            /*for(j = 7; j > 0; j--) {
               x >>= 1;
               if(x == 0) {
                  n += j;
                  break;
               }
            }
            break;*/
		n += clz(x);
		break;
         }
         n += 8;
      }

if (n>=c_difficulty) {
	printf("found!! t: %d, n: %d\n", thread, n);
}
	  if (n >= c_difficulty && !atomic_xchg(g_found, 1)) {
	  //if (thread == 122868 && !atomic_xchg(g_found,1)) {
		  /* PRINCESS FOUND! */
#ifdef DEBUG
		  printf("t: %d, n: %d\n", thread, n);
		  printf("sm: %d, %d, %d, %d, %d, %d, %d, %d\n",
				  sm_chain[0], sm_chain[1], sm_chain[2], sm_chain[3],
				  sm_chain[4], sm_chain[5], sm_chain[6], sm_chain[7]);
#endif
         #pragma unroll
         for (i = 0; i < 16; i++) {
            g_seed[i] = seed[i];
            //g_seed[i] = l_tile[i];
	    //g_seed[i] = l_input[i];
	 }
#ifdef DEBUG
		printf("n: %d, c_difficulty: %d\n", n, c_difficulty);
		printf16("seed: ", seed);
		printf32("hash: ", fhash);
		printf32("bt_hash: ", bt_hash);
#endif
      }
      /* Our princess is in another castle ! */
   }
   else {
#ifdef DEBUG
	   printf("WARNING: thread >= threads: %d\n", thread);
#endif
   }
}



/*
 * nighthash.c  FPGA-Confuddling Hash Algo
 *
 * Copyright (c) 2019 by Adequate Systems, LLC.  All Rights Reserved.
 * See LICENSE.PDF   **** NO WARRANTY ****
 *
 * Date: 12 June 2019
 * Revision: 1
 *
 * This file is subject to the license as found in LICENSE.PDF
 *
 */

/**
 * Performs data transformation on 32 bit chunks (4 bytes) of data
 * using deterministic floating point operations on IEEE 754
 * compliant machines and devices.
 * @param *data     - pointer to in data (at least 32 bytes)
 * @param len       - length of data
 * @param index     - the current tile
 * @param *op       - pointer to the operator value
 * @param transform - flag indicates to transform the input data */
void cl_fp_operation_transform_32B(uint8_t *data, uint32_t index, uint32_t *op) {
   uint8_t *temp;
   const const uint32_t adjustedlen = 32;
   int32_t i, j, operand;
   float floatv, floatv1;
   float *floatp;
   
   /* Work on data 4 bytes at a time */
#pragma unroll 16
   for(i = 0; i < adjustedlen; i += 4)
   {
      /* Cast 4 byte piece to float pointer */
         floatp = (float *) &data[i];

      /* 4 byte separation order depends on initial byte:
       * #1) *op = data... determine floating point operation type
       * #2) operand = ... determine the value of the operand
       * #3) if(data[i ... determine the sign of the operand
       *                   ^must always be performed after #2) */
      uint d7 = data[i] & 7;
      if (d7 == 0) {
            *op += data[i + 1];
            operand = data[i + 2];
            if(data[i + 3] & 1) operand ^= 0x80000000;
      } else if (d7 == 1) {
            operand = data[i + 1];
            if(data[i + 2] & 1) operand ^= 0x80000000;
            *op += data[i + 3];
      } else if (d7 == 2) {
            *op += data[i];
            operand = data[i + 2];
            if(data[i + 3] & 1) operand ^= 0x80000000;
      } else if (d7 == 3) {
            *op += data[i];
            operand = data[i + 1];
            if(data[i + 2] & 1) operand ^= 0x80000000;
      } else if (d7 == 4) {
            operand = data[i];
            if(data[i + 1] & 1) operand ^= 0x80000000;
            *op += data[i + 3];
      } else if (d7 == 5) {
            operand = data[i];
            if(data[i + 1] & 1) operand ^= 0x80000000;
            *op += data[i + 2];
      } else if (d7 == 6) {
            *op += data[i + 1];
            operand = data[i + 1];
            if(data[i + 3] & 1) operand ^= 0x80000000;
      } else if (d7 == 7) {
            operand = data[i + 1];
            *op += data[i + 2];
            if(data[i + 3] & 1) operand ^= 0x80000000;
      }

      /* Cast operand to float */
      floatv = operand;

      /* Replace pre-operation NaN with index */
      if(isnan(*floatp)) *floatp = index;

      /* Perform predetermined floating point operation */
      uint lop = *op & 3;
      if (lop == 0) {
            *floatp += floatv;
      } else if (lop == 1) {
            *floatp -= floatv;
      } else if (lop == 2) {
            *floatp *= floatv;
      } else if (lop == 3) {
            *floatp /= floatv;
      }

      /* Replace post-operation NaN with index */
      if(isnan(*floatp)) *floatp = index;

      /* Add result of floating point operation to op */
      temp = (uint8_t *) floatp;
      for(j = 0; j < 4; j++) {
         *op += temp[j];
      }
   } /* end for(*op = 0... */
}

void cl_fp_operation_transform_36B(uint8_t *data, uint32_t index, uint32_t *op) {
   uint8_t *temp;
   const uint32_t adjustedlen = 36;
   int32_t i, j, operand;
   float floatv;
   float *floatp;
   
   /* Work on data 4 bytes at a time */
#pragma unroll 18
   for(i = 0; i < adjustedlen; i += 4)
   {
      /* Cast 4 byte piece to float pointer */
         floatp = (float *) &data[i];

      /* 4 byte separation order depends on initial byte:
       * #1) *op = data... determine floating point operation type
       * #2) operand = ... determine the value of the operand
       * #3) if(data[i ... determine the sign of the operand
       *                   ^must always be performed after #2) */
      uint d7 = data[i] & 7;
      if (d7 == 0) {
            *op += data[i + 1];
            operand = data[i + 2];
            if(data[i + 3] & 1) operand ^= 0x80000000;
      } else if (d7 == 1) {
            operand = data[i + 1];
            if(data[i + 2] & 1) operand ^= 0x80000000;
            *op += data[i + 3];
      } else if (d7 == 2) {
            *op += data[i];
            operand = data[i + 2];
            if(data[i + 3] & 1) operand ^= 0x80000000;
      } else if (d7 == 3) {
            *op += data[i];
            operand = data[i + 1];
            if(data[i + 2] & 1) operand ^= 0x80000000;
      } else if (d7 == 4) {
            operand = data[i];
            if(data[i + 1] & 1) operand ^= 0x80000000;
            *op += data[i + 3];
      } else if (d7 == 5) {
            operand = data[i];
            if(data[i + 1] & 1) operand ^= 0x80000000;
            *op += data[i + 2];
      } else if (d7 == 6) {
            *op += data[i + 1];
            operand = data[i + 1];
            if(data[i + 3] & 1) operand ^= 0x80000000;
      } else if (d7 == 7) {
            operand = data[i + 1];
            *op += data[i + 2];
            if(data[i + 3] & 1) operand ^= 0x80000000;
      }

      /* Cast operand to float */
      floatv = operand;

      /* Replace pre-operation NaN with index */
      if(isnan(*floatp)) *floatp = index;

      /* Perform predetermined floating point operation */
      uint lop = *op & 3;
      if (lop == 0) {
            *floatp += floatv;
      } else if (lop == 1) {
            *floatp -= floatv;
      } else if (lop == 2) {
            *floatp *= floatv;
      } else if (lop == 3) {
            *floatp /= floatv;
      }

      /* Replace post-operation NaN with index */
      if(isnan(*floatp)) *floatp = index;

      /* Add result of floating point operation to op */
      temp = (uint8_t *) floatp;
      for(j = 0; j < 4; j++) {
         *op += temp[j];
      }
   } /* end for(*op = 0... */
}

/**
 * Performs data transformation on 32 bit chunks (4 bytes) of data
 * using deterministic floating point operations on IEEE 754
 * compliant machines and devices.
 * @param *data     - pointer to in data (at least 32 bytes)
 * @param len       - length of data
 * @param index     - the current tile
 * @param *op       - pointer to the operator value
 * @param transform - flag indicates to transform the input data */
uint32_t cl_fp_operation_notransform_1060B(uint8_t *data, uint32_t index, uint32_t op)
{
   const uint32_t adjustedlen = 1060;
   int32_t i, j, operand;
   float floatv, floatv1;
   
   /* Work on data 4 bytes at a time */
#pragma unroll 10
   for(i = 0; i < adjustedlen; i += 4) {
	uchar udata[4];
	udata[0] = data[i];
	udata[1] = data[i+1];
	udata[2] = data[i+2];
	udata[3] = data[i+3];
      /* Cast 4 byte piece to float pointer */
        // floatv1 = *(float *) &data[i];
      floatv1 = as_float(*((uint*)(udata)));

      /* 4 byte separation order depends on initial byte:
       * #1) *op = data... determine floating point operation type
       * #2) operand = ... determine the value of the operand
       * #3) if(data[i ... determine the sign of the operand
       *                   ^must always be performed after #2) */
      uint d7 = udata[0] & 7;
      uchar op0 = (d7 == 2) | (d7 == 3);
      uchar op1 = (d7 == 0) | (d7 == 6);
      uchar op2 = (d7 == 5) | (d7 == 7);
      uchar op3 = (d7 == 1) | (d7 == 4);
      if (op0) {
	      op += udata[0];
      } else if (op1) {
	      op += udata[1];
      } else if (op2) {
	      op += udata[2];
      } else if (op3) {
	      op += udata[3];
      }
      uchar oper0 = (d7 == 4) | (d7 == 5);
      uchar oper1 = (d7 == 1) | (d7 == 3) | (d7 == 6) | (d7 == 7);
      uchar oper2 = (d7 == 0) | (d7 == 2);
      if (oper0) {
	      operand = udata[0];
      } else if (oper1) {
	      operand = udata[1];
      } else if (oper2) {
	      operand = udata[2];
      }
      //uchar sign1 = (d7 == 4) | (d7 == 5);
      uchar sign1 = oper0;
      uchar sign2 = (d7 == 1) | (d7 == 3);
      uchar sign3 = (d7 == 0) | (d7 == 2) | (d7 == 6) | (d7 == 7);
      if (sign1 && (udata[1] & 1)) {
            operand ^= 0x80000000;
      } else if (sign2 && (udata[2] & 1)) {
            operand ^= 0x80000000;
      } else if (sign3 && (udata[3] & 1)) {
            operand ^= 0x80000000;
      }

      /* Cast operand to float */
      floatv = operand;

      /* Replace pre-operation NaN with index */
      if(isnan(floatv1)) floatv1 = index;

      /* Perform predetermined floating point operation */
      uint lop = op & 3;
      if (lop == 0) {
            floatv1 += floatv;
      } else if (lop == 1) {
            floatv1 -= floatv;
      } else if (lop == 2) {
            floatv1 *= floatv;
      } else if (lop == 3) {
            floatv1 /= floatv;
      }

      /* Replace post-operation NaN with index */
      if(isnan(floatv1)) floatv1 = index;

      /* Add result of floating point operation to op */
      uint utemp = as_uint(floatv1);
      uchar *temp = (uchar*)&utemp;
      for(j = 0; j < 4; j++) {
         op += temp[j];
      }
   } /* end for(*op = 0... */
   return op;
}


/**
 * Performs bit/byte operations on all data (len) of data using
 * random bit/byte transform operations, for increased complexity
 * @param *data     - pointer to in data
 * @param len       - length of data
 * @param *op       - pointer to the operator value */
uint32_t cl_bitbyte_transform(uint8_t *data, uint32_t len, uint32_t op)
{
   /* Perform <TILE_TRANSFORMS> number of bit/byte manipulations */
#pragma unroll
   for(int32_t i = 0; i < TILE_TRANSFORMS; i++)
   {
      /* Determine operation to use this iteration */
      op += data[i & 31];

      uint sel = op & 7;

      if (sel == 0) { /* Swap the first and last bit in each byte. */
	      for(int idx = 0; idx < len; ++idx)
		      data[idx] ^= 0x81;
      } else if (sel == 1) { /* Swap bytes */
	      for(int idx = 0; idx < (len >> 1); ++idx) {
		      uint tmp = data[idx];
		      data[idx] = data[idx + (len >> 1)];
		      data[idx + (len >> 1)] = tmp;
	      }
      } else if (sel == 2) { /* Complement One, all bytes */
	      for(int idx = 0; idx < len; ++idx)
		      data[idx] = ~data[idx];
      } else if (sel == 3) { /* Alternate +1 and -1 on all bytes */
	      for(int idx = 0; idx < len; ++idx)
		      data[idx] += ((idx & 1) == 0) ? 1 : -1;
      } else if (sel == 4) { /* Alternative +i and -i on all bytes */
	      for(int idx = 0; idx < len; ++idx)
		      data[idx] += ((idx & 1) == 0) ? -i : i;
      } else if (sel == 5) { /* Replace every occurence of 104 with 72 */
	      for(int idx = 0; idx < len; ++idx)
		      data[idx] = ((data[idx] == 104) ? 72 : data[idx]);
      } else if (sel == 6) { /* If a > b, swap them */
	      for(int idx = 0; idx < (len >> 1); ++idx) {
		      if(data[idx] > data[idx + (len >> 1)]) {
			      uint tmp = data[idx];
			      data[idx] = data[idx + (len >> 1)];
			      data[idx + (len >> 1)] = tmp;
		      }
	      }
      } else { /* XOR all bytes */
	      for(int idx = 1; idx < len; ++idx)
		      data[idx] ^= data[idx - 1];
      }
   } /* end for(i = 0... */ 
   return op;
}

void cl_nighthash_init_common(CUDA_NIGHTHASH_CTX *ctx, uint32_t algo_type) {
	/* Clear nighthash context */
	for (int i = 0; i < sizeof(CUDA_NIGHTHASH_CTX); i++) {
		((uint8_t*)ctx)[i] = 0;
	}

	ctx->algo_type = algo_type & 7;

	if (ctx->algo_type == 6) {
		cl_md2_init(&(ctx->md2));
	} else if (ctx->algo_type == 7) {
		cl_md5_init(&(ctx->md5));
	}
}

void cl_nighthash_init_transform_32B(CUDA_NIGHTHASH_CTX *ctx, uint8_t *algo_type_seed, uint32_t index) {
	uint32_t algo_type;
	algo_type = 0;

	/* Perform floating point operations to transform (if transform byte is set)
	 * input data and determine algo type */
	cl_fp_operation_transform_32B(algo_type_seed, index, &algo_type);

	/* Perform bit/byte transform operations to transform (if transform byte is set)
	 * input data and determine algo type */
	algo_type = cl_bitbyte_transform(algo_type_seed, 32, algo_type);

	cl_nighthash_init_common(ctx, algo_type);
}

void cl_nighthash_init_transform_36B(CUDA_NIGHTHASH_CTX *ctx, uint8_t *algo_type_seed, uint32_t index) {
	uint32_t algo_type;
	algo_type = 0;

	/* Perform floating point operations to transform (if transform byte is set)
	 * input data and determine algo type */
	cl_fp_operation_transform_36B(algo_type_seed, index, &algo_type);

	/* Perform bit/byte transform operations to transform (if transform byte is set)
	 * input data and determine algo type */
	algo_type = cl_bitbyte_transform(algo_type_seed, 36, algo_type);

	cl_nighthash_init_common(ctx, algo_type);
}

void cl_nighthash_init_notransform_1060B(CUDA_NIGHTHASH_CTX *ctx, uint8_t *algo_type_seed, uint32_t index) {
	uint32_t algo_type;
	algo_type = 0;

	/* Perform floating point operations to transform (if transform byte is set)
	 * input data and determine algo type */
	algo_type = cl_fp_operation_notransform_1060B(algo_type_seed, index, algo_type);

	cl_nighthash_init_common(ctx, algo_type);
}


void cl_nighthash_update(CUDA_NIGHTHASH_CTX *ctx, uint8_t *in, uint32_t inlen) {
	if (ctx->algo_type == 6) {
		cl_md2_update(&(ctx->md2), in, inlen);
	} else if (ctx->algo_type == 7) {
		cl_md5_update(&(ctx->md5), in, inlen);
	}
}

void cl_nighthash_final(CUDA_NIGHTHASH_CTX *ctx, uint8_t *out) {
	if (ctx->algo_type == 6) {
		cl_md2_final(&(ctx->md2), out);
		for (int i = 0; i < 16; i++) {
			((uint8_t*)(out+16))[i] = 0;
		}
	} else if (ctx->algo_type == 7) {
		cl_md5_final(&(ctx->md5), out);
		for (int i = 0; i < 16; i++) {
			((uint8_t*)(out+16))[i] = 0;
		}
	}
}

