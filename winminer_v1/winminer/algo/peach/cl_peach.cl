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

#if 0
#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <cl_runtime.h>
#include <time.h>

#include "../../sleep.h"
#include "../../config.h"

#include "../../types.h"

#include "peach.h"
#include "nighthash.cu"
#include "../../helpers.h"
#include "cl_peach.h"
#endif

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

   uint32_t digestlen;
   uint32_t algo_type;

   union {
	   CUDA_MD2_CTX md2;
	   CUDA_MD5_CTX md5;
   };

} CUDA_NIGHTHASH_CTX;

uint8_t *trigg_gen(uint8_t *in);
void cl_nighthash_init(CUDA_NIGHTHASH_CTX *ctx, uint8_t *algo_type_seed,
                                    uint32_t algo_type_seed_length, uint32_t index,
                                    uint8_t transform, uint8_t debug);
void cl_nighthash_update(CUDA_NIGHTHASH_CTX *ctx, uint8_t *in, uint32_t inlen, uint8_t debug);
void cl_nighthash_final(CUDA_NIGHTHASH_CTX *ctx, uint8_t *out, uint8_t debug);
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

/*__constant static uint8_t __align__(8) c_phash[32];
__constant static uint8_t __align__(8) c_input[108];
__constant static uint8_t __align__(8) c_difficulty;*/
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
   //memcpy(seed, nonce, HASHLEN);
    for (int i = 0; i < HASHLEN; i++) {
	    ((uint8_t*)seed)[i] = nonce[i];
    }
   //memcpy(seed + HASHLEN, (uint8_t *) &index, 4);
    for (int i = 0; i < 4; i++) {
	    ((uint8_t*)(seed+HASHLEN))[i] = ((uint8_t*)&index)[i];
    }
   //memcpy(seed + HASHLEN + 4, &g_map[index * TILE_LENGTH], TILE_LENGTH);
    for (int i = 0; i < TILE_LENGTH; i++) {
	    ((uint8_t*)(seed+HASHLEN+4))[i] = g_map[index*TILE_LENGTH + i];
    }

#ifdef DEBUG
   if (debug) {
	   printf32("first tile: ", (&g_map[index * TILE_LENGTH]));
	   /*printf("first tile: ");
	   for (int i = 0; i < TILE_LENGTH; i++) {
		   printf("%02x ", g_map[index * TILE_LENGTH + i]);
	   }
	   printf("\n");*/

	   printf32("cl_next_index seed: ", seed);
	   /*printf("cl_next_index seed: ");
	   for (int i = 0; i < seedlen; i++) {
		   printf("%02x ", seed[i]);
	   }
	   printf("\n");*/
   }
#endif
   
   /* Setup nighthash the seed, NO TRANSFORM */
   cl_nighthash_init(&nighthash, seed, seedlen, index, 0, debug);

   if (nighthash.algo_type == 0) {
	   Blake2B_K32_1060B((uchar*)hash, (uchar*)seed);
   } else if (nighthash.algo_type == 1) {
	   Blake2B_K64_1060B((uchar*)hash, (uchar*)seed);
   } else if (nighthash.algo_type == 2) {
	   SHA1Digest1060B((uchar*)hash, (uchar*)seed);
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
	   cl_nighthash_update(&nighthash, seed, seedlen, debug);

	   /* Finalize nighthash into the first 32 byte chunk of the tile */
	   cl_nighthash_final(&nighthash, hash, debug);
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
   //memcpy(seed + 4, c_phash, HASHLEN);
    for (int i = 0; i < HASHLEN; i++) {
	    (seed+4)[i] = ((__global uint8_t*)c_phash)[i];
    }

   /* Setup nighthash with a transform of the seed */
   cl_nighthash_init(&nighthash, seed, seedlen, index, 1, debug);

   if (nighthash.algo_type == 0) {
	   Blake2B_K32_36B((uchar*)local_out, (uchar*)seed);
   } else if (nighthash.algo_type == 1) {
	   Blake2B_K64_36B((uchar*)local_out, (uchar*)seed);
   } else if (nighthash.algo_type == 2) {
	   SHA1Digest36B((uchar*)local_out, (uchar*)seed);
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
	   cl_nighthash_update(&nighthash, seed, seedlen, debug);

	   /* Finalize nighthash into the first 32 byte chunk of the tile */
	   cl_nighthash_final(&nighthash, local_out, debug);
   }

   for (int i = 0; i < HASHLEN; i++) {
	   tilep[i] = local_out[i];
   }

   /* Begin constructing the full tile */
   for(i = 0, j = HASHLEN; j < TILE_LENGTH; i += HASHLEN, j += HASHLEN) { /* For each tile row */
	   /* Hash the current row to the next, if not at the end */
	   /* Setup nighthash with a transform of the current row */
	   cl_nighthash_init(&nighthash, local_out, HASHLEN, index, 1, debug);
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
		   SHA1Digest36B((uchar*)local_out, (uchar*)local_out);
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
		   cl_nighthash_update(&nighthash, local_out, HASHLEN+4, debug);
		   //cl_nighthash_update(&nighthash, (uint8_t *) &index, 4, debug);

		   /* Finalize nighthash into the first 32 byte chunk of the tile */
		   /*if (debug) {
			   printf("tilep[%d] = %02x\n", i, local_out[0]);
		   }*/
		   cl_nighthash_final(&nighthash, local_out, debug);
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

/*   if (thread == 0) {
	   printf("tile 0: ");
	   for (int i = 0; i < TILE_LENGTH; i++) {
		   printf("%02x ", g_map[i]);
	   }
	   printf("\n");
   }*/
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

      /*printf("Seed: ");
      for (int j = 0; j < 16; j++) {
	      printf("%02x ", seed[j]);
      }
      printf("\n");*/

      /* store full nonce */
      #pragma unroll
      for (i = 0; i < 16; i++)
         nonce[i] = c_input[i + 92];

      #pragma unroll
      for (i = 0; i < 16; i++)
         nonce[i+16] = seed[i];

      /*printf("Nonce: ");
      for (int j = 0; j < 32; j++) {
	      printf("%02x ", nonce[j]);
      }
      printf("\n");*/

      /*********************************************************/
      /* Hash 124 bytes of Block Trailer, including both seeds */

      uint8_t l_input[124];
      for (int i = 0; i < 108; i++) {
	      l_input[i] = c_input[i];
      }
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
#if 0
		printf("l_tile: ");
		for (int j = 0; j < HASHLEN; j++) {
#ifdef AMD
			printf("%02x ", l_tile[j]);
#else
			printf("%02x ", g_map[sm*TILE_LENGTH+j]);
#endif
		}
		printf("\n");
#endif
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

#if 0
#include "../../crypto/hash/cuda/blake2b.cu"
#include "../../crypto/hash/cuda/keccak.cu"
#include "../../crypto/hash/cuda/sha256.cu"
#include "../../crypto/hash/cuda/sha1.cu"
#include "../../crypto/hash/cuda/md5.cu"
#include "../../crypto/hash/cuda/md2.cu"
#include "../../types.h"
#include "peach.h"
#endif

/**
 * Performs data transformation on 32 bit chunks (4 bytes) of data
 * using deterministic floating point operations on IEEE 754
 * compliant machines and devices.
 * @param *data     - pointer to in data (at least 32 bytes)
 * @param len       - length of data
 * @param index     - the current tile
 * @param *op       - pointer to the operator value
 * @param transform - flag indicates to transform the input data */
void cl_fp_operation(uint8_t *data, uint32_t len, uint32_t index,
                                  uint32_t *op, uint8_t transform, uint8_t debug)
{
   uint8_t *temp;
   uint32_t adjustedlen;
   int32_t i, j, operand;
   float floatv, floatv1;
   float *floatp;
   
   /* Adjust the length to a multiple of 4 */
   adjustedlen = (len >> 2) << 2;

   /* Work on data 4 bytes at a time */
   for(i = 0; i < adjustedlen; i += 4)
   {
      /* Cast 4 byte piece to float pointer */
      if(transform)
         floatp = (float *) &data[i];
      else {
         floatv1 = *(float *) &data[i];
         floatp = &floatv1;
      }

      /* 4 byte separation order depends on initial byte:
       * #1) *op = data... determine floating point operation type
       * #2) operand = ... determine the value of the operand
       * #3) if(data[i ... determine the sign of the operand
       *                   ^must always be performed after #2) */
#ifdef DEBUG
      if (debug) {
	      printf("data[i] & 7 = %d\n", data[i] & 7);
      }
#endif
      switch(data[i] & 7)
      {
         case 0:
            *op += data[i + 1];
            operand = data[i + 2];
            if(data[i + 3] & 1) operand ^= 0x80000000;
            break;
         case 1:
            operand = data[i + 1];
            if(data[i + 2] & 1) operand ^= 0x80000000;
            *op += data[i + 3];
            break;
         case 2:
            *op += data[i];
            operand = data[i + 2];
            if(data[i + 3] & 1) operand ^= 0x80000000;
            break;
         case 3:
            *op += data[i];
            operand = data[i + 1];
            if(data[i + 2] & 1) operand ^= 0x80000000;
            break;
         case 4:
            operand = data[i];
            if(data[i + 1] & 1) operand ^= 0x80000000;
            *op += data[i + 3];
            break;
         case 5:
            operand = data[i];
            if(data[i + 1] & 1) operand ^= 0x80000000;
            *op += data[i + 2];
            break;
         case 6:
            *op += data[i + 1];
            operand = data[i + 1];
            if(data[i + 3] & 1) operand ^= 0x80000000;
            break;
         case 7:
            operand = data[i + 1];
            *op += data[i + 2];
            if(data[i + 3] & 1) operand ^= 0x80000000;
            break;
      } /* end switch(data[j] & 31... */

      /* Cast operand to float */
      floatv = operand;
#ifdef DEBUG
      if (debug) {
	      printf("floatv: %f\n", floatv);
      }
#endif

      /* Replace pre-operation NaN with index */
      if(isnan(*floatp)) *floatp = index;
#ifdef DEBUG
      if (debug){
	      printf("*floatp: %f\n", *floatp);
      }
#endif

      /* Perform predetermined floating point operation */
#ifdef DEBUG
      if (debug) {
	      printf("*op & 3 = %d\n", *op & 3);
      }
#endif
      switch(*op & 3) {
         case 0:
            *floatp += floatv;
            break;
         case 1:
            *floatp -= floatv;
            break;
         case 2:
            *floatp *= floatv;
            break;
         case 3:
            *floatp /= floatv;
            break;
      }

      /* Replace post-operation NaN with index */
      if(isnan(*floatp)) *floatp = index;
#ifdef DEBUG
      if (debug) {
	      printf("*floatp: %f\n", *floatp);
      }
#endif

      /* Add result of floating point operation to op */
      temp = (uint8_t *) floatp;
      for(j = 0; j < 4; j++) {
#ifdef DEBUG
	      if (debug) {
	      printf("*op += %d\n", temp[j]);
	      }
#endif
         *op += temp[j];
      }
#ifdef DEBUG
      if (debug) {
	      printf("*op: %d\n", *op);
      }
#endif
   } /* end for(*op = 0... */
}


/**
 * Performs bit/byte operations on all data (len) of data using
 * random bit/byte transform operations, for increased complexity
 * @param *data     - pointer to in data
 * @param len       - length of data
 * @param *op       - pointer to the operator value */
void cl_bitbyte_transform(uint8_t *data, uint32_t len, uint32_t *op)
{
   int32_t i, z;
   uint32_t len2;
   uint8_t temp, _104, _72;

   /* Perform <TILE_TRANSFORMS> number of bit/byte manipulations */
   for(i = 0, _104 = 104, _72 = 72, len2 = len/2; i < TILE_TRANSFORMS; i++)
   {
      /* Determine operation to use this iteration */
      *op += data[i & 31];

      /* Perform random operation */
      switch(*op & 7) {
         case 0: /* Swap the first and last bit in each byte. */
            for(z = 0; z < len; z++)
               data[z] ^= 0x81;
            break;
         case 1: /* Swap bytes */
            for(z = 0; z < len2; z++) {
               temp = data[z];
               data[z] = data[z + len2];
               data[z + len2] = temp;
            }
            break;
         case 2: /* Complement One, all bytes */
            for(z = 0; z < len; z++)
               data[z] = ~data[z];
            break;
         case 3: /* Alternate +1 and -1 on all bytes */
            for(z = 0; z < len; z++)
               data[z] += ((z & 1) == 0) ? 1 : -1;
            break;
         case 4: /* Alternate +i and -i on all bytes */
            for(z = 0; z < len; z++)
               data[z] += ((z & 1) == 0) ? -i : i;
            break;
         case 5: /* Replace every occurrence of _104 with _72 */ 
            for(z = 0; z < len; z++)
               if(data[z] == _104) data[z] = _72;
            break;
         case 6: /* If byte a is > byte b, swap them. */
            for(z = 0; z < len2; z++) {
               if(data[z] > data[z + len2]) {
                  temp = data[z];
                  data[z] = data[z + len2];
                  data[z + len2] = temp;
               }
            }
            break;
         case 7: /* XOR all bytes */
            for(z = 1; z < len; z++)
               data[z] ^= data[z - 1];
            break;
      } /* end switch(... */
   } /* end for(i = 0... */ 
}

void cl_nighthash_init(CUDA_NIGHTHASH_CTX *ctx, uint8_t *algo_type_seed,
                                    uint32_t algo_type_seed_length, uint32_t index,
                                    uint8_t transform, uint8_t debug)
{
   uint32_t algo_type;
   uint8_t key32[32], key64[64];
   algo_type = 0;
   
   /* Perform floating point operations to transform (if transform byte is set)
    * input data and determine algo type */
   cl_fp_operation(algo_type_seed, algo_type_seed_length, index, &algo_type, transform, debug);
#ifdef DEBUG
   if (debug) {
	   printf("fp: algo_type: %d\n", algo_type);
   }
#endif
   
   /* Perform bit/byte transform operations to transform (if transform byte is set)
    * input data and determine algo type */
   if(transform) {
      cl_bitbyte_transform(algo_type_seed, algo_type_seed_length, &algo_type);
   }
#ifdef DEBUG
   if (debug) {
	   printf("transform?: %d: algo_type: %d\n", transform, algo_type);
   }
#endif
   
   /* Clear nighthash context */
   //memset(ctx, 0, sizeof(CUDA_NIGHTHASH_CTX));
   for (int i = 0; i < sizeof(CUDA_NIGHTHASH_CTX); i++) {
	   ((uint8_t*)ctx)[i] = 0;
   }

   ctx->digestlen = 32;
   ctx->algo_type = algo_type & 7;
   
#ifdef DEBUG
   if (debug) {
	   printf("algo_type: %d\n", ctx->algo_type);
   }
#endif

   switch(ctx->algo_type)
   {
      case 0:
#if 0
         //memset(key32, ctx->algo_type, 32);
	   for (int i = 0; i < 32; i++) {
		   ((uint8_t*)key32)[i] = ctx->algo_type;
	   }
#ifdef DEBUG
	   if (debug) {
		   printf("blake2b_init, key32: ");
		   for (int i = 0; i < 32; i++) {
			   printf("%02x ", key32[i]);
		   }
		   printf("\n");
	   }
#endif
         cl_blake2b_init(&(ctx->blake2b), key32, 32, 256, debug);
#endif
         break;
      case 1:
#if 0
         //memset(key64, ctx->algo_type, 64);
	   for (int i = 0; i < 64; i++) {
		   ((uint8_t*)key64)[i] = ctx->algo_type;
	   }
#ifdef DEBUG
	   if (debug) {
		   printf32("blake2b_init, key64: ", key64);
		   /*printf("blake2b_init, key64: ");
		   for (int i = 0; i < 64; i++) {
			   printf("%02x ", key64[i]);
		   }
		   printf("\n");*/
	   }
#endif
         cl_blake2b_init(&(ctx->blake2b), key64, 64, 256, debug);
#endif
         break;
      case 2:
         //cl_sha1_init(&(ctx->sha1));
         break;
      case 3:
         //cl_sha256_init(&(ctx->sha256));
         break;
      case 4:
         //cl_keccak_sha3_init(&(ctx->sha3), 256);
         break;
      case 5:
         //cl_keccak_init(&(ctx->keccak), 256);
         break;
      case 6:
         cl_md2_init(&(ctx->md2));
         break;
      case 7:
         cl_md5_init(&(ctx->md5));
         break;
   } /* end switch(algo_type)... */
}

void cl_nighthash_update(CUDA_NIGHTHASH_CTX *ctx, uint8_t *in, uint32_t inlen, uint8_t debug)
{
   switch(ctx->algo_type)
   {
      case 0:
#if 0
         cl_blake2b_update(&(ctx->blake2b), in, inlen);
#ifdef DEBUG
		 if (debug) {
			 printf("blake2b(0) update: inlen: %d, in: ", inlen);
			 for (int i = 0; i < inlen; i++) {
				 printf("%02x ", in[i]);
			 }
			 printf("\n");
		 }
#endif
#endif
         break;
      case 1:
#if 0
         cl_blake2b_update(&(ctx->blake2b), in, inlen);
#ifdef DEBUG
		 if (debug) {
			 if (inlen >= 32) {
				 printf32("blake2b(1) update: ", in);
			 } else if (inlen >= 16) {
				 printf16("blake2b(1) update: ", in);
			 } else {
				 printf("blake2b(1) update: ");
				 for (int i = 0; i < inlen; i++) {
					 printf("%02x ", in[i]);
				 }
				 printf("\n");
			 }
		 }
#endif
#endif
         break;
      case 2:
#if 0
         cl_sha1_update(&(ctx->sha1), in, inlen);
#ifdef DEBUG
		 if (debug) {
			 printf("sha1 update: ");
			 for (int i = 0; i < inlen; i++) {
				 printf("%02x ", in[i]);
			 }
			 printf("\n");
		 }
#endif
#endif
         break;
      case 3:
         //cl_sha256_update(&(ctx->sha256), in, inlen);
         break;
      case 4:
         //cl_keccak_update(&(ctx->sha3), in, inlen, debug);
         break;
      case 5:
         //cl_keccak_update(&(ctx->keccak), in, inlen, debug);
         break;
      case 6:
         cl_md2_update(&(ctx->md2), in, inlen);
#ifdef DEBUG
		 if (debug) {
			 printf("md2 update: ");
			 for (int i = 0; i < inlen; i++) {
				 printf("%02x ", in[i]);
			 }
			 printf("\n");
		 }
#endif
         break;
      case 7:
         cl_md5_update(&(ctx->md5), in, inlen);
#ifdef DEBUG
		 if (debug) {
			 printf("md5 update: ");
			 for (int i = 0; i < inlen; i++) {
				 printf("%02x ", in[i]);
			 }
			 printf("\n");
		 }
#endif
         break;
   } /* end switch(ctx->... */
}

void cl_nighthash_final(CUDA_NIGHTHASH_CTX *ctx, uint8_t *out, uint8_t debug)
{
   switch(ctx->algo_type)
   {
      case 0:
#if 0
         cl_blake2b_final(&(ctx->blake2b), out);
#ifdef DEBUG
		 if (debug) {
			 printf("blake2b(0) final: "
					 "%02x %02x %02x %02x "
					 "%02x %02x %02x %02x "
					 "%02x %02x %02x %02x "
					 "%02x %02x %02x %02x "
					 "%02x %02x %02x %02x "
					 "%02x %02x %02x %02x "
					 "%02x %02x %02x %02x "
					 "%02x %02x %02x %02x\n",
					 out[0], out[1], out[2], out[3],
					 out[4], out[5], out[6], out[7],
					 out[8], out[9], out[10], out[11],
					 out[12], out[13], out[14], out[15],
					 out[16], out[17], out[18], out[19],
					 out[20], out[21], out[22], out[23],
					 out[24], out[25], out[26], out[27],
					 out[28], out[29], out[30], out[31]);
		 }
#endif
#endif
         break;
      case 1:
#if 0
         cl_blake2b_final(&(ctx->blake2b), out);
#ifdef DEBUG
		 if (debug) {
			 printf("blake2b(1) final: "
					 "%02x %02x %02x %02x "
					 "%02x %02x %02x %02x "
					 "%02x %02x %02x %02x "
					 "%02x %02x %02x %02x "
					 "%02x %02x %02x %02x "
					 "%02x %02x %02x %02x "
					 "%02x %02x %02x %02x "
					 "%02x %02x %02x %02x\n",
					 out[0], out[1], out[2], out[3],
					 out[4], out[5], out[6], out[7],
					 out[8], out[9], out[10], out[11],
					 out[12], out[13], out[14], out[15],
					 out[16], out[17], out[18], out[19],
					 out[20], out[21], out[22], out[23],
					 out[24], out[25], out[26], out[27],
					 out[28], out[29], out[30], out[31]);
		 }
#endif
#endif
         break;
      case 2:
#if 0
         cl_sha1_final(&(ctx->sha1), out);
         //memset(out + 20, 0, 12);
	   for (int i = 0; i < 12; i++) {
		   ((uint8_t*)(out+20))[i] = 0;
	   }
#ifdef DEBUG
		 if (debug) {
			 printf("sha1 final: "
					 "%02x %02x %02x %02x "
					 "%02x %02x %02x %02x "
					 "%02x %02x %02x %02x "
					 "%02x %02x %02x %02x "
					 "%02x %02x %02x %02x "
					 "%02x %02x %02x %02x "
					 "%02x %02x %02x %02x "
					 "%02x %02x %02x %02x\n",
					 out[0], out[1], out[2], out[3],
					 out[4], out[5], out[6], out[7],
					 out[8], out[9], out[10], out[11],
					 out[12], out[13], out[14], out[15],
					 out[16], out[17], out[18], out[19],
					 out[20], out[21], out[22], out[23],
					 out[24], out[25], out[26], out[27],
					 out[28], out[29], out[30], out[31]);
		 }
#endif
#endif
         break;
      case 3:
         //cl_sha256_final(&(ctx->sha256), out);
         break;
      case 4:
         //cl_keccak_final(&(ctx->sha3), out, debug);
         break;
      case 5:
         //cl_keccak_final(&(ctx->keccak), out, debug);
         break;
      case 6:
         cl_md2_final(&(ctx->md2), out);
         //memset(out + 16, 0, 16);
	   for (int i = 0; i < 16; i++) {
		   ((uint8_t*)(out+16))[i] = 0;
	   }
         break;
      case 7:
         cl_md5_final(&(ctx->md5), out);
         //memset(out + 16, 0, 16);
	   for (int i = 0; i < 16; i++) {
		   ((uint8_t*)(out+16))[i] = 0;
	   }
         break;
      default:
	 break;
   } /* end switch(ctx->... */
}

