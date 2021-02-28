/*
 * cl_trigg.cu  Multi-GPU CUDA Mining
 *
 * Copyright (c) 2019 by Adequate Systems, LLC.  All Rights Reserved.
 * See LICENSE.PDF   **** NO WARRANTY ****
 *
 * Date: 10 August 2018
 * Revision: 31
 */

#define DEBUG_TILEP
//#define DEBUG_FLOAT

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


#define HASHLEN                        32
#define TILE_ROWS                      32
#define TILE_LENGTH (TILE_ROWS * HASHLEN)
#define TILE_TRANSFORMS                 8
#define MAP                       1048576
#define MAP_LENGTH    (TILE_LENGTH * MAP)
#define JUMP                            8

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

void cl_nighthash_init_transform_32B(CUDA_NIGHTHASH_CTX *ctx, uint8_t *algo_type_seed, uint32_t index);
void cl_nighthash_init_transform_36B(CUDA_NIGHTHASH_CTX *ctx, uint8_t *algo_type_seed, uint32_t index);
void cl_nighthash_init_notransform_1060B(CUDA_NIGHTHASH_CTX *ctx, uint8_t *algo_type_seed, uint32_t index);
void cl_nighthash_algoinit(CUDA_NIGHTHASH_CTX *ctx);
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

uint32_t cl_next_index(uint32_t index, __global uint8_t *g_map, uint8_t *nonce, uint8_t *scratch) {
   CUDA_NIGHTHASH_CTX nighthash;

   //uint8_t seed[HASHLEN + 4 + TILE_LENGTH];
   uint8_t *seed = scratch;
   const int seedlen = HASHLEN + 4 + TILE_LENGTH;

   uint32_t hash[HASHLEN/4];

   /* Create nighthash seed for this index on the map */
   #pragma unroll
   for (int i = 0; i < HASHLEN/8; i++) {
	   ((uint64_t*)seed)[i] = ((uint64_t*)(nonce))[i];
   }
   ((uint32_t*)(seed+HASHLEN))[0] = ((uint32_t*)&index)[0];
   #pragma unroll
   for (int i = 0; i < TILE_LENGTH/4; i++) {
	   ((uint32_t*)(seed+HASHLEN+4))[i] = ((global uint32_t*)(g_map+index*TILE_LENGTH))[i];
   }
   
   /* Setup nighthash the seed, NO TRANSFORM */
   cl_nighthash_init_notransform_1060B(&nighthash, seed, index);

   if (nighthash.algo_type == 0) {
	   Blake2B_K32_1060B((uchar*)hash, (uchar*)seed);
   } else if (nighthash.algo_type == 1) {
	   Blake2B_K64_1060B((uchar*)hash, (uchar*)seed);
   } else if (nighthash.algo_type == 2) {
	   SHA1Digest1060B((uint*)hash, (uint*)seed);
	   #pragma unroll
	   for (int i = 0; i < 3; i++) {
		   ((uint32_t*)(hash+20))[i] = 0;
	   }
   } else if (nighthash.algo_type == 3) {
	   SHA2_256_1056B_1060B((uint*)hash, (uint*)seed, true);
   } else if (nighthash.algo_type == 4) {
	   SHA3Digest1060B((ulong*)hash, (ulong*)seed);
   } else if (nighthash.algo_type == 5) {
	   Keccak256Digest1060B((ulong*)hash, (ulong*)seed);
   } else {
	   cl_nighthash_algoinit(&nighthash);
	   /* Update nighthash with the seed data */
	   cl_nighthash_update(&nighthash, seed, seedlen);

	   /* Finalize nighthash into the first 32 byte chunk of the tile */
	   cl_nighthash_final(&nighthash, (uint8_t*)hash);
   }

   /* Convert 32-byte Hash Value Into 8x 32-bit Unsigned Integer */
   index = 0;
   #pragma unroll
   for(int i = 0; i < 8; i+=4) {
      index += hash[i] + hash[i+1] + hash[i+2] + hash[i+3];
   }

   return index & 0xfffff; // equivalent to index % MAP
}


void cl_gen_tile(uint32_t index, __global uint8_t *g_map, uint8_t debug, __global uint8_t *c_phash)
{
   CUDA_NIGHTHASH_CTX nighthash;
   const int seedlen = 4 + HASHLEN;
   uint8_t seed[4 + HASHLEN];
   uint8_t local_out[4 + HASHLEN];

   /* Set map pointer */
   global uint8_t *tilep = &g_map[index * TILE_LENGTH];

   /* Create nighthash seed for this index on the map */
   ((uint32_t*)(seed))[0] = ((uint32_t*)&index)[0];
   #pragma unroll
   for (int i = 0; i < HASHLEN/4; i++) {
	   ((uint32_t*)(seed+4))[i] = ((__global uint32_t*)c_phash)[i];
   }

   /* Setup nighthash with a transform of the seed */
   cl_nighthash_init_transform_36B(&nighthash, seed, index);

   if (nighthash.algo_type == 0) {
	   Blake2B_K32_36B((uchar*)local_out, (uchar*)seed);
   } else if (nighthash.algo_type == 1) {
	   Blake2B_K64_36B((uchar*)local_out, (uchar*)seed);
   } else if (nighthash.algo_type == 2) {
	   SHA1Digest36B((uint*)local_out, (uint*)seed);
	   #pragma unroll
	   for (int i = 0; i < 3; i++) {
		   ((uint32_t*)(local_out+20))[i] = 0;
	   }
   } else if (nighthash.algo_type == 3) {
	   SHA2_256_36B((uint*)local_out, (uint*)seed);
   } else if (nighthash.algo_type == 4) {
	   SHA3256Digest36B((ulong*)local_out, (ulong*)seed);
   } else if (nighthash.algo_type == 5) {
	   Keccak256Digest36B((ulong*)local_out, (ulong*)seed);
   } else {
	   cl_nighthash_algoinit(&nighthash);
	   /* Update nighthash with the seed data */
	   cl_nighthash_update(&nighthash, seed, seedlen);

	   /* Finalize nighthash into the first 32 byte chunk of the tile */
	   cl_nighthash_final(&nighthash, local_out);
   }

   #pragma unroll
   for (int i = 0; i < HASHLEN/8; i++) {
	   ((global uint64_t*)(tilep))[i] = ((uint64_t*)(local_out))[i];
   }

   /* Begin constructing the full tile */
   for(int i = 0, j = HASHLEN; j < TILE_LENGTH; i += HASHLEN, j += HASHLEN) { /* For each tile row */
	   /* Hash the current row to the next, if not at the end */
	   /* Setup nighthash with a transform of the current row */
#ifdef DEBUG_TILEP
	   if (index == 1 && i >= 100 && i <= 300) {
		   printf("tilep %d, algotype: %d\n", i, nighthash.algo_type);
		   printf32("", (tilep+i));
	   }
#endif
	   cl_nighthash_init_transform_32B(&nighthash, local_out, index);
	   #pragma unroll
	   for (int z = 0; z < HASHLEN/8; z++) {
		   ((global uint64_t*)(tilep+i))[z] = ((uint64_t*)(local_out))[z];
	   }
#ifdef DEBUG_TILEP
	   if (index == 1 && i >= 100 && i <= 300) {
		   printf("tilep %d, algotype: %d\n", i, nighthash.algo_type);
		   printf32("", (tilep+i));
	   }
#endif
	   ((uint32_t*)(local_out+HASHLEN))[0] = ((uint32_t*)&index)[0];

	   if (nighthash.algo_type == 0) {
		   Blake2B_K32_36B((uchar*)local_out, (uchar*)local_out);
	   } else if (nighthash.algo_type == 1) {
		   Blake2B_K64_36B((uchar*)local_out, (uchar*)local_out);
	   } else if (nighthash.algo_type == 2) {
		   SHA1Digest36B((uint*)local_out, (uint*)local_out);
		   #pragma unroll
		   for (int i = 0; i < 3; i++) {
			   ((uint32_t*)(local_out+20))[i] = 0;
		   }
	   } else if (nighthash.algo_type == 3) {
		   SHA2_256_36B((uint*)local_out, (uint*)local_out);
	   } else if (nighthash.algo_type == 4) {
		   SHA3256Digest36B((ulong*)local_out, (ulong*)local_out);
	   } else if (nighthash.algo_type == 5) {
		   Keccak256Digest36B((ulong*)local_out, (ulong*)local_out);
	   } else {
		   /* Update nighthash with the seed data and tile index */
		   cl_nighthash_algoinit(&nighthash);
		   cl_nighthash_update(&nighthash, local_out, HASHLEN+4);
		   cl_nighthash_final(&nighthash, local_out);
	   }
	   #pragma unroll
	   for (int z = 0; z < HASHLEN/8; z++) {
		   ((global uint64_t*)(tilep+j))[z] = ((uint64_t*)(local_out))[z];
	   }
#if 0
	   if (index == 0 && i >= 96 && i <= 128) {
		   //printf("tilep %d, algotype: %d\n", j, nighthash.algo_type);
		   printf32("", (tilep+j));
	   }
#endif
   }
}


__kernel void cl_build_map(__global uint8_t *g_map, __global uint8_t *c_phash, uint32_t start_index) {
   uint32_t thread = get_global_id(0) + start_index;
   //if (thread < MAP) {
   if (thread < 2) {
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

   if (thread < threads && thread < 131072) {
      /* Determine second seed */
      //if(thread < 131072) { /* This frame permutations: 131,072 */
         seed[ 0] = Z_TIME[(thread & 15)];
         seed[ 1] = Z_AMB[(thread >> 4) & 15];
         seed[ 2] = 1;
         seed[ 3] = Z_ADJ[(thread >> 8) & 63];
         seed[ 4] = Z_MASS[(thread >> 14) & 3];
         seed[ 5] = 1;
         seed[ 6] = Z_ING[(thread >> 16) & 1];
      //}

      /* store full nonce */
      #pragma unroll
      for (int i = 0; i < 16; i++)
         nonce[i] = c_input[i + 92];

      #pragma unroll
      for (int i = 0; i < 16; i++)
         nonce[i+16] = seed[i];

      /*********************************************************/
      /* Hash 124 bytes of Block Trailer, including both seeds */

      uint8_t l_input[124];
      #pragma unroll
      for (int i = 0; i < 108/4; i++) {
	      ((uint32_t*)(l_input))[i] = ((global uint32_t*)(c_input))[i];
      }
      #pragma unroll
      for (int i = 0; i < 16; i++) {
	      l_input[108+i] = nonce[16+i];
      }
      SHA2_256_124B((uint*)bt_hash, (uint*)l_input);

      /****************************************************/
      /* Follow the tile path based on the selected nonce */
      
      uint32_t sm = bt_hash[0];
      #pragma unroll
      for(int i = 1; i < HASHLEN; i++) {
         sm *= bt_hash[i];
      }
      //sm %= MAP;
      sm &= 0xfffff; // equivalent to sm %= MAP

      /* make <JUMP> tile jumps to find the final tile */
      #pragma unroll
      for(int j = 0; j < JUMP; j++) {
        sm = cl_next_index(sm, g_map, nonce, scratch);
      }

      /****************************************************************/
      /* Check the hash of the final tile produces the desired result */

      uint64_t btbuf[HASHLEN+TILE_LENGTH];
      #pragma unroll
      for (int i = 0; i < HASHLEN/8; i++) {
	      btbuf[i] = ((uint64_t*)bt_hash)[i];
      }
      #pragma unroll
      for (int i = 0; i < TILE_LENGTH/8; i++) {
	      btbuf[HASHLEN/8+i] = ((global uint64_t*)(g_map+sm*TILE_LENGTH))[i];
      }
      SHA2_256_1056B_1060B((uint*)fhash, (uint*)btbuf, false);

      /* Evaluate hash */
      int32_t n = 0;
      for (int32_t i = 0; i < HASHLEN; i++) {
	      uint8_t x = fhash[i];
	      if (x != 0) {
		      n += clz(x);
		      break;
	      }
	      n += 8;
      }

      if (n >= c_difficulty) {
	      printf("found!! t: %d, n: %d\n", thread, n);
      }

      if (n >= c_difficulty && !atomic_xchg(g_found, 1)) {
	      /* PRINCESS FOUND! */
	      #pragma unroll
	      for (int i = 0; i < 2; i++) {
		      ((global uint64_t*)(g_seed))[i] = ((uint64_t*)(seed))[i];
	      }
      }
      /* Our princess is in another castle ! */
   }
#ifdef DEBUG
   else {
	   printf("WARNING: thread >= threads: %d\n", thread);
   }
#endif
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
double float_to_double(uint32_t sp) {
	// Normals and denormals
	short sign = (sp & (1<<31)) ? -1 : +1;
	//print("Sign:", "-" if (sp_hex & (1<<31)) else "+");
	int exponent = (sp & 0x7f800000) >> 23;
	//print("Exponent:", exponent)
	//print("bin:", bin(exponent))
	uint64_t mantissa = (sp & 0x7fffff);
	mantissa <<= 29;
	for (int i = 0; i < 23; i++) {
		if ( (mantissa & (1<<51)) == 0) {
			mantissa <<= 1;
			exponent -= 1;
		} else {
			break;
		}
	}
	exponent += 1023 - 127;

	//de = exponent - 1023;
	//print("ex:", de, (de - (-1023)))
	//print("bin mantissa:", bin(mantissa))
	//print("hex mantissa:", hex(mantissa))
	//fmantissa = float(mantissa) / (1<<52);
	//if (exponent != 0) {
		//fmantissa += 1;
	//}
	//print("Mantissa:", fmantissa)
	//dval = sign*(2**(exponent-1023))*fmantissa;
	//print(dval)
	//print("double hex:", double_to_hex(dval))
	uint64_t dval2 = ((sign == -1) << 63);
	dval2 |= exponent << 52;
	dval2 |= mantissa;
	//print("dval2:", hex(dval2))
	return as_double(dval2);
}
#endif


#if 0
uint32_t double_to_float(double d) {
    // Normals and denormals
	ulong dp = as_ulong(d);
	uint sign        = (dp & 0x8000000000000000) >> 32;
    uint dp_exponent = (dp & 0x7ff0000000000000) >> 52;
    int exponent     = dp_exponent - 1023 + 127;
    uint mantissa    = (dp & 0x000fffffe0000000) >> 29;
	int sh = dp_exponent - 897; // exponent - 1023 + 126
	printf("sh: %d\n", sh);
    if (sh < 0) {
        mantissa |= (1<<23);
        mantissa >>= (-sh-1);
		mantissa += 1;
		mantissa >>= 1;
        exponent = 0;
	}
	printf("sign: %d, mantissa: %d, exponent: %d\n", sign, mantissa, exponent);
    uint32_t fval2 = sign;
    fval2 |= (exponent & 0xff) << 23;
    fval2 |= (mantissa & 0x7fffff);

	return fval2;
}
#endif

double float_to_double(uint32_t a) {
	uint64_t z = 0;
	uint64_t z_e = 0;
	uint64_t z_m = 0;

	/* Sign bit */
	uint64_t sign = 0;
	if (a & (1 << 31)) {
		sign = (1UL << 63);
	}
	z |= sign;

	uint32_t a_exp = (a >> 23) & 0xff;
	uint64_t a_frac = a & 0x7fffff;

	z = z | (a_frac << 29);


	/*printf("a_exp = %d\n", a_exp);
	printf("a_frac = %lu\n", a_frac);*/
	if (a_exp == 0) {
		//printf("a_exp == 0\n");
		if (a & 0xffffff) {
			z_e = 897;
			z_m = a_frac << 29;
			//printf("z_m: %016lx\n", z_m);

			/* Normalize */
			for (;;) {
				//printf("z_m: %016lx\n", z_m);
				if (z_m & (1UL<<52)) {
					z = sign;
					/*printf("z: %016lx\n", z);
					printf("z_e: %ld, %08lx\n", z_e, z_e);*/
					z = z | (z_e << 52);
					//printf("z: %016lx\n", z);
					z = z | (z_m & 0xfffffffffffff);
					//printf("z: %016lx\n", z);
					break;
				} else {
					z_m = (z_m & 0xfffffffffffff) << 1;
					z_e = z_e - 1;
					//printf("z_e: %ld, %08lx\n", z_e, z_e);
				}
			}
			/* End normalize */
		}
	} else if (a_exp == 255) {
		//printf("a_exp == 255\n");
		z = z | (2047UL << 52);
	} else {
		//printf("other a_exp\n");
		//printf("z before: %016lx\n", z);
		uint64_t exp = (a_exp - 127) + 1023;
		uint64_t exp_shift = exp << 52;
		//printf("exp: %lu\n", exp<<52);
		z = z | exp_shift;
		//printf("z after: %016lx\n", z);
	}
	return *(double*)((void*)&z);
}

uint32_t double_to_float(double d) {
	uint64_t a = *(uint64_t*)((void*)&d);
	uint32_t z = 0;
	uint32_t z_e = 0;
	uint32_t z_m = 0;
	uint32_t sticky = 0;
	uint32_t guard = 0;
	uint32_t round = 0;

	/*
	 * sign = a[63]
	 * exponent = a[62:52]
	 * fraction = a[51:0]
	 */

	/* Sign bit */
	if (a & ((uint64_t)1<<63)) {
		z |= (1<<31);
	}

	uint32_t a_exp = ((a >> 52) & 0x7ff);
	uint64_t a_frac = a & 0xfffffffffffff;
	uint32_t a_frac29 = a_frac >> 29;
	/*printf("a_exp: %d\n", a_exp);
	printf("a_frac29: %08x\n", a_frac29);*/

	if (a_exp == 0) {
		/* z is 0 except for sign bit */
	} else if (a_exp < 897) {
		/* z_exp is 0 */
		z_m = (1<<23) | (a_frac29);
		z_e = a_exp;
		guard = a & (1<<28);
		round = a & (1<<27);
		sticky = ((a & 0x7ffffff) != 0);

		/* Denormalize */
		for (;;) {
			//printf("denormalize\n");
			if (z_e == 897 || (z_m == 0 && guard == 0)) {
				if (guard && (round || sticky)) {
					//printf("guard && (round || sticky)\n");
					z |= (z_m + 1) & 0x7fffff;
				} else {
					//printf("not guard\n");
					z |= z_m & 0x7fffff;
				}
				/*printf("z: %08x\n", z);
				printf("z_m: %08x\n", z_m);
				printf("z_e: %08x\n", z_e);*/
				break;
			} else {
				z_e = z_e + 1;
				sticky = sticky | round;
				round = guard;
				guard = z_m & 0x1;
				z_m = z_m >> 1;
			}
		}
		/* End denormalize */
	} else if (a_exp == 2047) {
		z |= (255 << 23);
		if (a_frac) {
			z |= (1<<22);
		}
	} else if (a_exp > 1150) {
		z |= (255 << 23);
	} else {
		uint32_t exp = ((a_exp - 1023) + 127);
		if ((a & (1<<28)) && ( (a & (1<<27)) || (a & 0x7ffffff) )) {
			uint32_t frac = (a_frac29 + 1);
			if (frac & (1<<23)) {
				exp = exp + 1;
			}
			z |= (exp << 23) | (frac & 0x7fffff);
		} else {
			z |= (exp << 23) | ((a_frac29) & 0x7fffff);
		}
	}

	return z;
}

uint32_t cl_fp_operation_transform_inner(uint8_t *data, uint32_t index, uint32_t op) {
	int32_t operand;
	float floatv;
	float *floatp;
	double d, dv;

	uchar udata[4];
	((uint*)udata)[0] = ((uint*)(data))[0];
	/* Cast 4 byte piece to float pointer */
	floatp = (float*)udata;
#ifdef DEBUG_FLOAT
	if (index == 0) printf("udata[0]: %d, udata[1]: %d, udata[2]: %d, udata[3]: %d\n", udata[0], udata[1], udata[2], udata[3]);
	if (index == 0) printf("*floatp: %e\n", *floatp); 
#endif

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
	op += (op0) ? udata[0] : 0;
	op += (op1) ? udata[1] : 0;
	op += (op2) ? udata[2] : 0;
	op += (op3) ? udata[3] : 0;
	uchar oper0 = (d7 == 4) | (d7 == 5);
	uchar oper1 = (d7 == 1) | (d7 == 3) | (d7 == 6) | (d7 == 7);
	uchar oper2 = (d7 == 0) | (d7 == 2);
	operand = oper0 ? udata[0] : operand;
	operand = oper1 ? udata[1] : operand;
	operand = oper2 ? udata[2] : operand;
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
	//dv = float_to_double(as_uint(operand));
	dv = float_to_double(as_uint(floatv));
#ifdef DEBUG_FLOAT
	if (index == 0) printf("floatv: %e, dv: %e\n", floatv, dv);
#endif

	/* Replace pre-operation NaN with index */
	if (isnan(*floatp)) {
		*floatp = index;
	}

	//d = *floatp;
	d = float_to_double(*(uint32_t*)udata);
#ifdef DEBUG_FLOAT
	if (index == 0) printf("*floatp: %e, d: %e\n", *floatp, d);
#endif

	/* Perform predetermined floating point operation */
	uint lop = op & 3;
#ifdef DEBUG_FLOAT
	if (index == 0) printf("lop: %d\n", lop);
#endif
	if (lop == 0) {
		/*printf("add\n");
		printf("*floatp: %08x, floatv: %08x\n", as_uint(*floatp), as_uint(floatv));
		printf("d: %016x, dv: %016x\n", as_ulong(d), as_ulong(dv));*/
		//*floatp += floatv;
		d += dv;
		/*printf("*floatp: %08x, floatv: %08x\n", as_uint(*floatp), as_uint(floatv));
		printf("d: %016x, dv: %016x\n", as_ulong(d), as_ulong(dv));
		uint32_t *ivp = (uint32_t*)floatp;
		printf("f: %08x\n", *ivp);*/
		uint32_t f = double_to_float(d);
		/*ivp = (uint32_t*)&f;
		printf("d: %08x\n", *ivp);*/
		*((uint32_t*)udata) = *((uint32_t*)&f);
	} else if (lop == 1) {
		/*printf("subtract\n");
		printf("*floatp: %08x, floatv: %08x\n", as_uint(*floatp), as_uint(floatv));
		printf("d: %016x, dv: %016x\n", as_ulong(d), as_ulong(dv));*/
		//*floatp -= floatv;
		d -= dv;
		/*printf("*floatp: %08x, floatv: %08x\n", as_uint(*floatp), as_uint(floatv));
		printf("d: %016x, dv: %016x\n", as_ulong(d), as_ulong(dv));
		uint32_t *ivp = (uint32_t*)floatp;
		printf("f: %08x\n", *ivp);*/
		uint32_t f = double_to_float(d);
		/*ivp = (uint32_t*)&f;
		printf("d: %08x\n", *ivp);*/
		*((uint32_t*)udata) = *((uint32_t*)&f);
	} else if (lop == 2) {
		/*printf("multiply\n");
		printf("*floatp: %08x, floatv: %08x\n", as_uint(*floatp), as_uint(floatv));
		printf("d: %016x, dv: %016x\n", as_ulong(d), as_ulong(dv));*/
		//*floatp *= floatv;
		d *= dv;
		/*printf("*floatp: %08x, floatv: %08x\n", as_uint(*floatp), as_uint(floatv));
		printf("d: %016x, dv: %016x\n", as_ulong(d), as_ulong(dv));*/
		//uint32_t *ivp = (uint32_t*)floatp;
		//printf("f: %08x\n", *ivp);
		uint32_t f = double_to_float(d);
		//ivp = (uint32_t*)&f;
		//printf("d: %08x\n", *ivp);
		//((uint32_t*)udata)[0] = ivp[0];
		*((uint32_t*)udata) = *((uint32_t*)&f);
	} else if (lop == 3) {
		/*printf("divide\n");
		printf("*floatp: %08x, floatv: %08x\n", as_uint(*floatp), as_uint(floatv));
		printf("d: %016x, dv: %016x\n", as_ulong(d), as_ulong(dv));*/
		//*floatp /= floatv;
		d /= dv;
		/*printf("*floatp: %08x, floatv: %08x\n", as_uint(*floatp), as_uint(floatv));
		printf("d: %016x, dv: %016x\n", as_ulong(d), as_ulong(dv));*/
		//uint32_t *ivp = (uint32_t*)floatp;
		//printf("f: %08x\n", *ivp);
		uint32_t f = double_to_float(d);
		//ivp = (uint32_t*)&f;
		//printf("d: %08x\n", *ivp);
		//((uint32_t*)udata)[0] = ivp[0];
		*((uint32_t*)udata) = *((uint32_t*)&f);
	}
#ifdef DEBUG_FLOAT
	if (index == 0) printf("*floatp: %e, d: %e\n", *floatp, d);
#endif

	/* Replace post-operation NaN with index */
	if (isnan(*floatp)) {
		*floatp = index;
	}
		


#ifdef DEBUG_FLOAT
	if (index == 0) printf("*floatp: %e\n", *floatp);
#endif

	/* Add result of floating point operation to op */
	//uint8_t *temp = (uint8_t *) floatp;
	uint utemp = as_uint(*floatp);
	uint8_t *temp = (uchar*)&utemp;
	op += temp[0] + temp[1] + temp[2] + temp[3];

	((uint*)(data))[0] = ((uint*)udata)[0];

#ifdef DEBUG_FLOAT
	if (index == 0) {
		printf("*floatp: %e, temp[0]: %d, temp[1]: %d, temp[2]: %d, temp[3]: %d, op: %d\n", *floatp, temp[0], temp[1], temp[2], temp[3], op);
	}
#endif
	return op;
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
uint32_t cl_fp_operation_transform_32B(uint8_t *data, uint32_t index) {
   const uint32_t adjustedlen = 32;
   uint32_t op = 0;
   
   /* Work on data 4 bytes at a time */
   #pragma unroll
   for(int i = 0; i < adjustedlen; i += 4) {
	   op = cl_fp_operation_transform_inner(data+i, index, op);
   } /* end for(*op = 0... */
   return op;
}

uint32_t cl_fp_operation_transform_36B(uint8_t *data, uint32_t index) {
   const uint32_t adjustedlen = 36;
   uint32_t op = 0;
   
   /* Work on data 4 bytes at a time */
   #pragma unroll
   for (int i = 0; i < adjustedlen; i += 4) {
	   op = cl_fp_operation_transform_inner(data+i, index, op);
   } /* end for(*op = 0... */
   return op;
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
uint32_t cl_fp_operation_notransform_1060B(uint8_t *data, uint32_t index) {
   const uint32_t adjustedlen = 1060;
   uint32_t op = 0;
   
   /* Work on data 4 bytes at a time */
   #pragma unroll 10
   for(int i = 0; i < adjustedlen; i += 4) {
      int32_t operand = 0;
      float floatv, floatv1;
      uchar udata[4];
      ((uint*)udata)[0] = ((uint*)(data+i))[0];
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
      op += (op0) ? udata[0] : 0;
      op += (op1) ? udata[1] : 0;
      op += (op2) ? udata[2] : 0;
      op += (op3) ? udata[3] : 0;
      uchar oper0 = (d7 == 4) | (d7 == 5);
      uchar oper1 = (d7 == 1) | (d7 == 3) | (d7 == 6) | (d7 == 7);
      uchar oper2 = (d7 == 0) | (d7 == 2);
      operand = oper0 ? udata[0] : operand;
      operand = oper1 ? udata[1] : operand;
      operand = oper2 ? udata[2] : operand;
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
      if (isnan(floatv1)) floatv1 = index;

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
      if (isnan(floatv1)) floatv1 = index;

      /* Add result of floating point operation to op */
      uint utemp = as_uint(floatv1);
      uchar *temp = (uchar*)&utemp;
      op += temp[0] + temp[1] + temp[2] + temp[3];
   } /* end for(*op = 0... */
   return op;
}


/**
 * Performs bit/byte operations on all data (len) of data using
 * random bit/byte transform operations, for increased complexity
 * @param *data     - pointer to in data
 * @param len       - length of data
 * @param *op       - pointer to the operator value */
uint32_t cl_bitbyte_transform(uint8_t *data, uint32_t len, uint32_t op) {
   /* Perform <TILE_TRANSFORMS> number of bit/byte manipulations */
   //#pragma unroll
   for(int32_t i = 0; i < TILE_TRANSFORMS; i++) {
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

void cl_nighthash_init_transform_32B(CUDA_NIGHTHASH_CTX *ctx, uint8_t *algo_type_seed, uint32_t index) {
	/* Perform floating point operations to transform (if transform byte is set)
	 * input data and determine algo type */
	uint32_t algo_type = cl_fp_operation_transform_32B(algo_type_seed, index);

#if 0
	   if (index == 0) {
		   printf("algo_type: %d\n", algo_type);
		   printf32("pre_bitbyte: ", (algo_type_seed));
	   }
#endif
	/* Perform bit/byte transform operations to transform (if transform byte is set)
	 * input data and determine algo type */
	algo_type = cl_bitbyte_transform(algo_type_seed, 32, algo_type);

#if 0
	   if (index == 0) {
		   printf("algo_type: %d\n", algo_type);
		   printf32("post_bitbyte: ", (algo_type_seed));
	   }
#endif

	ctx->algo_type = algo_type & 7;
}

void cl_nighthash_init_transform_36B(CUDA_NIGHTHASH_CTX *ctx, uint8_t *algo_type_seed, uint32_t index) {
	/* Perform floating point operations to transform (if transform byte is set)
	 * input data and determine algo type */
	uint32_t algo_type = cl_fp_operation_transform_36B(algo_type_seed, index);

	/* Perform bit/byte transform operations to transform (if transform byte is set)
	 * input data and determine algo type */
	algo_type = cl_bitbyte_transform(algo_type_seed, 36, algo_type);

	ctx->algo_type = algo_type & 7;
}

void cl_nighthash_init_notransform_1060B(CUDA_NIGHTHASH_CTX *ctx, uint8_t *algo_type_seed, uint32_t index) {
	/* Perform floating point operations to transform (if transform byte is set)
	 * input data and determine algo type */
	uint32_t algo_type = cl_fp_operation_notransform_1060B(algo_type_seed, index);
	ctx->algo_type = algo_type & 7;
}

void cl_nighthash_algoinit(CUDA_NIGHTHASH_CTX *ctx) {
	if (ctx->algo_type == 6) {
		cl_md2_init(&(ctx->md2));
	} else if (ctx->algo_type == 7) {
		cl_md5_init(&(ctx->md5));
	}
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
		for (int i = 0; i < 2; i++) {
			((uint64_t*)(out+16))[i] = 0;
		}
	} else if (ctx->algo_type == 7) {
		cl_md5_final(&(ctx->md5), out);
		for (int i = 0; i < 2; i++) {
			((uint64_t*)(out+16))[i] = 0;
		}
	}
}

