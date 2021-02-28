/*
 * cl_trigg.cu  Multi-GPU CUDA Mining
 *
 * Copyright (c) 2019 by Adequate Systems, LLC.  All Rights Reserved.
 * See LICENSE.PDF   **** NO WARRANTY ****
 *
 * Date: 10 August 2018
 * Revision: 31
 */

//#define DEBUG_TILEP
//#define DEBUG_FLOAT
#define DEBUG_THREAD 3

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
   if (thread < 10) {
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

	/* Special cases where the function misbehaves */
#if 0
	if (a == 0xC29E8C8A70000000UL) return 0xD4F46454; // 0xD4F46453
        else if (a == 0xbb5cda9ab0000000UL) return 0x9ae6d4d6; // 0x9ae6d4d5
	else if (a == 0xc5b50ad970000000UL) return 0xeda856cc; // 0xeda856cb
	else if (a == 0xb808a69360000000UL) return 0x80629a4e; // 0x80629a4d
	else if (a == 0xbe0fa73270000000UL) return 0xb07d3994; // 0xb07d3993
	else if (a == 0xc1e03385f0000000UL) return 0xcf019c30; // 0xcf019c2f
	else if (a == 0x4064232830000000UL) return 0x43211942; // 0x43211941
	else if (a == 0xc55f574130000000UL) return 0xeafaba0a; // 0xeafaba09
	else if (a == 0x3a9b38b570000000UL) return 0x14d9c5ac; // 0x14d9c5ab
	else if (a == 0x41e2961530000000UL) return 0x4f14b0aa; // 0x4f14b0a9
	else if (a == 0xbe1fa41e30000000UL) return 0xb0fd20f2; // 0xb0fd20f1
	else if (a == 0x436679dbf0000000UL) return 0x5b33cee0; // 0x5b33cedf
	else if (a == 0xc0605ad0f0000000UL) return 0xc302d688; // 0xc302d687
	else if (a == 0x410fc449f0000000UL) return 0x487e2250; // 0x487e224f
	else if (a == 0x3e6b721e30000000UL) return 0x335b90f2; // 0x335b90f1
	else if (a == 0xbebb07cef0000000UL) return 0xb5d83e78; // 0xb5d83e77
	else if (a == 0x4186441fb0000000UL) return 0x4c3220fe; // 0x4c3220fd
	else if (a == 0x4193f99a70000000UL) return 0x4c9fccd4; // 0x4c9fccd3
	else if (a == 0xb80a24d660000000UL) return 0x8068935a; // 0x80689359
	else if (a == 0x4587c40270000000UL) return 0x6c3e2014; // 0x6c3e2013
	else if (a == 0x42eef2ef70000000UL) return 0x5777977c; // 0x5777977b
	else if (a == 0x41d9692030000000UL) return 0x4ecb4902; // 0x4ecb4901
	else if (a == 0x466dbab5f0000000UL) return 0x736dd5b0; // 0x736dd5af
	else if (a == 0x3bafe127b0000000UL) return 0x1d7f093e; // 0x1d7f093d
	else if (a == 0x4065d42f70000000UL) return 0x432ea17c; // 0x432ea17b
	else if (a == 0x3c7507e030000000UL) return 0x23a83f02; // 0x23a83f01
	else if (a == 0x40661d70b0000000UL) return 0x4330eb86; // 0x4330eb85
	else if (a == 0xc369a5a7b0000000UL) return 0xdb4d2d3e; // 0xdb4d2d3d
	else if (a == 0xc1661b1370000000UL) return 0xcb30d89c; // 0xcb30d89b
	else if (a == 0xc4fc19fc70000000UL) return 0xe7e0cfe4; // 0xe7e0cfe3
	else if (a == 0x44858105f0000000UL) return 0x642c0830; // 0x642c082f
	else if (a == 0x3f7800ae30000000UL) return 0x3bc00572; // 0x3bc00571
	else if (a == 0xc1d8acb4f0000000UL) return 0xcec565a8; // 0xcec565a7
	else if (a == 0xc4eda27a30000000UL) return 0xe76d13d2; // 0xe76d13d1
	else if (a == 0xc362acaaf0000000UL) return 0xdb156558; // 0xdb156557
	else if (a == 0xc1e28a9d70000000UL) return 0xcf1454ec; // 0xcf1454eb
	else if (a == 0x436302c0f0000000UL) return 0x5b181608; // 0x5b181607
	else if (a == 0x47536ce930000000UL) return 0x7a9b674a; // 0x7a9b6749
	else if (a == 0xbdb1718270000000UL) return 0xad8b8c14; // 0xad8b8c13
	else if (a == 0xc1e1183570000000UL) return 0xcf08c1ac; // 0xcf08c1ab
	else if (a == 0x41804c7bf0000000UL) return 0x4c0263e0; // 0x4c0263df
	else if (a == 0xc18da75fb0000000UL) return 0xcc6d3afe; // 0xcc6d3afd
	else if (a == 0x43c0d41830000000UL) return 0x5e06a0c2; // 0x5e06a0c1
	else if (a == 0x3c8e024030000000UL) return 0x24701202; // 0x24701201
	else if (a == 0xc1db32e630000000UL) return 0xced99732; // 0xced99731
	else if (a == 0xbc75171570000000UL) return 0xa3a8b8ac; // 0xa3a8b8ab
	else if (a == 0xbcaf627770000000UL) return 0xa57b13bc; // 0xa57b13bb
	else if (a == 0xc1dfc08930000000UL) return 0xcefe044a; // 0xcefe0449
	else if (a == 0xc1e3e43ef0000000UL) return 0xcf1f21f8; // 0xcf1f21f7
	else if (a == 0x3d9d4f8b30000000UL) return 0x2cea7c5a; // 0x2cea7c59
	else if (a == 0xc500dc1030000000UL) return 0xe806e082; // 0xe806e081
	else if (a == 0x436241f130000000UL) return 0x5b120f8a; // 0x5b120f89
	else if (a == 0x3ca095a0b0000000UL) return 0x2504ad06; // 0x2504ad05
	else if (a == 0x4018b9b1f0000000UL) return 0x40c5cd90; // 0x40c5cd8f
	else if (a == 0x47379c5cb0000000UL) return 0x79bce2e6; // 0x79bce2e5
	else if (a == 0xbbff3efdf0000000UL) return 0x9ff9f7f0; // 0x9ff9f7ef
	else if (a == 0x41533117b0000000UL) return 0x4a9988be; // 0x4a9988bd
	else if (a == 0x41d422d730000000UL) return 0x4ea116ba; // 0x4ea116b9
	else if (a == 0xc6edb960b0000000UL) return 0xf76dcb06; // 0xf76dcb05
	else if (a == 0x3ef502e230000000UL) return 0x37a81712; // 0x37a81711
	else if (a == 0xb9ad99bdb0000000UL) return 0x8d6ccdee; // 0x8d6ccded
	else if (a == 0x439293b8b0000000UL) return 0x5c949dc6; // 0x5c949dc5
	else if (a == 0xc041cc1070000000UL) return 0xc20e6084; // 0xc20e6083
	else if (a == 0x41fe9807b0000000UL) return 0x4ff4c03e; // 0x4ff4c03d
	else if (a == 0x41f43f2270000000UL) return 0x4fa1f914; // 0x4fa1f913
	else if (a == 0x3ebf2fb6b0000000UL) return 0x35f97db6; // 0x35f97db5
	else if (a == 0xbb3f1c0a30000000UL) return 0x99f8e052; // 0x99f8e051
	else if (a == 0xc05af47bf0000000UL) return 0xc2d7a3e0; // 0xc2d7a3df
	else if (a == 0xb7d202c700000000UL) return 0x80090164; // 0x80090163
	else if (a == 0x4066a42330000000UL) return 0x4335211a; // 0x43352119
	else if (a == 0xc06d35b770000000UL) return 0xc369adbc; // 0xc369adbb
	else if (a == 0x43333a9c70000000UL) return 0x5999d4e4; // 0x5999d4e3
	else if (a == 0xc040ed3c30000000UL) return 0xc20769e2; // 0xc20769e1
	else if (a == 0x4361131ef0000000UL) return 0x5b0898f8; // 0x5b0898f7
	else if (a == 0x41d788fe30000000UL) return 0x4ebc47f2; // 0x4ebc47f1
	else if (a == 0xc1835a1c30000000UL) return 0xcc1ad0e2; // 0xcc1ad0e1
	else if (a == 0xc4cef768f0000000UL) return 0xe677bb48; // 0xe677bb47
	else if (a == 0x40196032b0000000UL) return 0x40cb0196; // 0x40cb0195
	else if (a == 0xbad7fc8270000000UL) return 0x96bfe414; // 0x96bfe413
	else if (a == 0xc19533d730000000UL) return 0xcca99eba; // 0xcca99eb9
	else if (a == 0xbf8c927770000000UL) return 0xbc6493bc; // 0xbc6493bb
	else if (a == 0x436602d430000000UL) return 0x5b3016a2; // 0x5b3016a1
	else if (a == 0x417d4df170000000UL) return 0x4bea6f8c; // 0x4bea6f8b
	else if (a == 0xc1874e6a70000000UL) return 0xcc3a7354; // 0xcc3a7353
	else if (a == 0x41f682e2f0000000UL) return 0x4fb41718; // 0x4fb41717
	else if (a == 0xc01201ee70000000UL) return 0xc0900f74; // 0xc0900f73
	else if (a == 0xc3da1d8570000000UL) return 0xded0ec2c; // 0xded0ec2b
	else if (a == 0x406ee884b0000000UL) return 0x43774426; // 0x43774425
        else if (a == 0xba1d1b74f0000000UL) return 0x90e8dba8; // 0x90e8dba7
	else if (a == 0x3720180000000000UL) return 0x00000102; // 0x00000101
	else if (a == 0x3720580000000000UL) return 0x00000106; // 0x00000105
	else if (a == 0x3720980000000000UL) return 0x0000010a; // 0x00000109
	else if (a == 0x3720d80000000000UL) return 0x0000010e; // 0x0000010d
	else if (a == 0x3723180000000000UL) return 0x00000132; // 0x00000131
	else if (a == 0x3723580000000000UL) return 0x00000136; // 0x00000135
	else if (a == 0x3723980000000000UL) return 0x0000013a; // 0x00000139
	else if (a == 0x3723d80000000000UL) return 0x0000013e; // 0x0000013d
	else if (a == 0x3727180000000000UL) return 0x00000172; // 0x00000171
	else if (a == 0x3727580000000000UL) return 0x00000176; // 0x00000175
	else if (a == 0x3727980000000000UL) return 0x0000017a; // 0x00000179
	else if (a == 0x3727d80000000000UL) return 0x0000017e; // 0x0000017d
	else if (a == 0x3724180000000000UL) return 0x00000142; // 0x00000141
	else if (a == 0x3724580000000000UL) return 0x00000146; // 0x00000145
	else if (a == 0x3724980000000000UL) return 0x0000014a; // 0x00000149
	else if (a == 0x3724d80000000000UL) return 0x0000014e; // 0x0000014d
	else if (a == 0x3721180000000000UL) return 0x00000112; // 0x00000111
	else if (a == 0x3721580000000000UL) return 0x00000116; // 0x00000115
	else if (a == 0x3721980000000000UL) return 0x0000011a; // 0x00000119
	else if (a == 0x3721d80000000000UL) return 0x0000011e; // 0x0000011d
	else if (a == 0x3722180000000000UL) return 0x00000122; // 0x00000121
	else if (a == 0x3722580000000000UL) return 0x00000126; // 0x00000125
	else if (a == 0x3722980000000000UL) return 0x0000012a; // 0x00000129
	else if (a == 0x3722d80000000000UL) return 0x0000012e; // 0x0000012d
	else if (a == 0x3725180000000000UL) return 0x00000152; // 0x00000151
	else if (a == 0x3725580000000000UL) return 0x00000156; // 0x00000155
	else if (a == 0x3725980000000000UL) return 0x0000015a; // 0x00000159
	else if (a == 0x3725d80000000000UL) return 0x0000015e; // 0x0000015d
	else if (a == 0x3726180000000000UL) return 0x00000162; // 0x00000161
	else if (a == 0x3726580000000000UL) return 0x00000166; // 0x00000165
	else if (a == 0x3726980000000000UL) return 0x0000016a; // 0x00000169
	else if (a == 0x3726d80000000000UL) return 0x0000016e; // 0x0000016d
	else if (a == 0xc2024231f0000000UL) return 0xd0121190; // 0xd012118f
	else if (a == 0xb9e5907d70000000UL) return 0x8f2c83ec; // 0x8f2c83eb
	else if (a == 0x3ba084a730000000UL) return 0x1d04253a; // 0x1d042539
	else if (a == 0xc3decbc3f0000000UL) return 0xdef65e20; // 0xdef65e1f
	else if (a == 0xc1d2ca4db0000000UL) return 0xce96526e; // 0xce96526d
	else if (a == 0x3d225963b0000000UL) return 0x2912cb1e; // 0x2912cb1d
	else if (a == 0xc0a1202870000000UL) return 0xc5090144; // 0xc5090143
	else if (a == 0xc19bbf80f0000000UL) return 0xccddfc08; // 0xccddfc07
	else if (a == 0xbce0881330000000UL) return 0xa704409a; // 0xa7044099
	else if (a == 0xc364467330000000UL) return 0xdb22339a; // 0xdb223399
	else if (a == 0xc06433d0f0000000UL) return 0xc3219e88; // 0xc3219e87
	else if (a == 0x41e8123fb0000000UL) return 0x4f4091fe; // 0x4f4091fd
	else if (a == 0x38edbb4ab0000000UL) return 0x076dda56; // 0x076dda55
	else if (a == 0xb80fa6a060000000UL) return 0x807e9a82; // 0x807e9a81
	else if (a == 0xc072e7af30000000UL) return 0xc3973d7a; // 0xc3973d79
	else if (a == 0x3eff287270000000UL) return 0x37f94394; // 0x37f94393
	else if (a == 0x4220f35630000000UL) return 0x51079ab2; // 0x51079ab1
	else if (a == 0x43612f97f0000000UL) return 0x5b097cc0; // 0x5b097cbf
	else if (a == 0x41ddd7ea70000000UL) return 0x4eeebf54; // 0x4eeebf53
	else if (a == 0xbb9ef653b0000000UL) return 0x9cf7b29e; // 0x9cf7b29d
	else if (a == 0xc452172d70000000UL) return 0xe290b96c; // 0xe290b96b
	else if (a == 0x3b8ed210b0000000UL) return 0x1c769086; // 0x1c769085
	else if (a == 0x406eda3670000000UL) return 0x4376d1b4; // 0x4376d1b3
	else if (a == 0xc4ebdc8870000000UL) return 0xe75ee444; // 0xe75ee443
	else if (a == 0x41f5a3dcf0000000UL) return 0x4fad1ee8; // 0x4fad1ee7
	else if (a == 0x41e88425b0000000UL) return 0x4f44212e; // 0x4f44212d
	else if (a == 0x4050803a70000000UL) return 0x428401d4; // 0x428401d3
	else if (a == 0xc1e15c8570000000UL) return 0xcf0ae42c; // 0xcf0ae42b
	else if (a == 0x436ea4f170000000UL) return 0x5b75278c; // 0x5b75278b
	else if (a == 0xc16ff21530000000UL) return 0xcb7f90aa; // 0xcb7f90a9
	else if (a == 0x41dbba1e70000000UL) return 0x4eddd0f4; // 0x4eddd0f3
	else if (a == 0xc065a368f0000000UL) return 0xc32d1b48; // 0xc32d1b47
	else if (a == 0xc060e278f0000000UL) return 0xc30713c8; // 0xc30713c7
	else if (a == 0x45c649e3f0000000UL) return 0x6e324f20; // 0x6e324f1f
	else if (a == 0x406af16e30000000UL) return 0x43578b72; // 0x43578b71
	else if (a == 0x46b5164370000000UL) return 0x75a8b21c; // 0x75a8b21b
	else if (a == 0x41dd5caa30000000UL) return 0x4eeae552; // 0x4eeae551
	else if (a == 0xc164a96870000000UL) return 0xcb254b44; // 0xcb254b43
	else if (a == 0x3cc9b54f30000000UL) return 0x264daa7a; // 0x264daa79
	else if (a == 0x4252070b30000000UL) return 0x5290385a; // 0x52903859
	else if (a == 0xc0626709f0000000UL) return 0xc3133850; // 0xc313384f
	else if (a == 0x46520463b0000000UL) return 0x7290231e; // 0x7290231d
	else if (a == 0xc06c6a29f0000000UL) return 0xc3635150; // 0xc363514f
	else if (a == 0x4193898e30000000UL) return 0x4c9c4c72; // 0x4c9c4c71
	else if (a == 0xc06252acf0000000UL) return 0xc3129568; // 0xc3129567
	else if (a == 0x4068678a30000000UL) return 0x43433c52; // 0x43433c51
	else if (a == 0x417124def0000000UL) return 0x4b8926f8; // 0x4b8926f7
	else if (a == 0x410b9da1f0000000UL) return 0x485ced10; // 0x485ced0f
	else if (a == 0x417b2f4570000000UL) return 0x4bd97a2c; // 0x4bd97a2b
	else if (a == 0xb8020160e0000000UL) return 0x80480584; // 0x80480583
	else if (a == 0x40688c88b0000000UL) return 0x43446446; // 0x43446445
	else if (a == 0x41f27abd30000000UL) return 0x4f93d5ea; // 0x4f93d5e9
	else if (a == 0xbff6ff06b0000000UL) return 0xbfb7f836; // 0xbfb7f835
	else if (a == 0xc06178f030000000UL) return 0xc30bc782; // 0xc30bc781
	else if (a == 0xc1d9849c30000000UL) return 0xcecc24e2; // 0xcecc24e1
	else if (a == 0xc2d5f92130000000UL) return 0xd6afc90a; // 0xd6afc909
	else if (a == 0x406fb667f0000000UL) return 0x437db340; // 0x437db33f
	else if (a == 0xc035d08bb0000000UL) return 0xc1ae845e; // 0xc1ae845d
	else if (a == 0xc17584deb0000000UL) return 0xcbac26f6; // 0xcbac26f5
	else if (a == 0xbd929ef4f0000000UL) return 0xac94f7a8; // 0xac94f7a7
	else if (a == 0xb85b971330000000UL) return 0x82dcb89a; // 0x82dcb899
	else if (a == 0x4203f3d5f0000000UL) return 0x501f9eb0; // 0x501f9eaf
	else if (a == 0x41851c41b0000000UL) return 0x4c28e20e; // 0x4c28e20d
	else if (a == 0x4036987eb0000000UL) return 0x41b4c3f6; // 0x41b4c3f5
	else if (a == 0x406d488e70000000UL) return 0x436a4474; // 0x436a4473
	else if (a == 0xb80d669060000000UL) return 0x80759a42; // 0x80759a41
	else if (a == 0x406d43d630000000UL) return 0x436a1eb2; // 0x436a1eb1
	else if (a == 0xb831233bb0000000UL) return 0x818919de; // 0x818919dd
	else if (a == 0xbf87301ff0000000UL) return 0xbc398100; // 0xbc3980ff
	else if (a == 0xbdeb275630000000UL) return 0xaf593ab2; // 0xaf593ab1
	else if (a == 0xbfca46a1f0000000UL) return 0xbe523510; // 0xbe52350f
	else if (a == 0x405c0b1530000000UL) return 0x42e058aa; // 0x42e058a9
	else if (a == 0xc19784f530000000UL) return 0xccbc27aa; // 0xccbc27a9
	else if (a == 0xc0902748f0000000UL) return 0xc4813a48; // 0xc4813a47
	else if (a == 0x436c64f670000000UL) return 0x5b6327b4; // 0x5b6327b3
	else if (a == 0xc19f958cb0000000UL) return 0xccfcac66; // 0xccfcac65
	else if (a == 0xb999212c30000000UL) return 0x8cc90962; // 0x8cc90961
	else if (a == 0x4461dc6e70000000UL) return 0x630ee374; // 0x630ee373
	else if (a == 0xbecfc033b0000000UL) return 0xb67e019e; // 0xb67e019d
	else if (a == 0xbe91cab130000000UL) return 0xb48e558a; // 0xb48e5589
	else if (a == 0xc092103a70000000UL) return 0xc49081d4; // 0xc49081d3
	else if (a == 0xc0726ed570000000UL) return 0xc39376ac; // 0xc39376ab
	else if (a == 0x380aa337e0000000UL) return 0x006a8ce0; // 0x006a8cdf
	else if (a == 0xc1d986afb0000000UL) return 0xcecc357e; // 0xcecc357d
	else if (a == 0x45d8a99230000000UL) return 0x6ec54c92; // 0x6ec54c91
	else if (a == 0x426d376930000000UL) return 0x5369bb4a; // 0x5369bb49
	else if (a == 0x4052a246f0000000UL) return 0x42951238; // 0x42951237
	else if (a == 0x4181d168b0000000UL) return 0x4c0e8b46; // 0x4c0e8b45
	else if (a == 0x3c1e8214f0000000UL) return 0x20f410a8; // 0x20f410a7
	else if (a == 0x41815a9df0000000UL) return 0x4c0ad4f0; // 0x4c0ad4ef
	else if (a == 0x3d60ffb470000000UL) return 0x2b07fda4; // 0x2b07fda3
	else if (a == 0xc06b8dab30000000UL) return 0xc35c6d5a; // 0xc35c6d59
	else if (a == 0xb87890fb70000000UL) return 0x83c487dc; // 0x83c487db
	else if (a == 0x414333b270000000UL) return 0x4a199d94; // 0x4a199d93
	else if (a == 0xc1d0430330000000UL) return 0xce82181a; // 0xce821819
	else if (a == 0x40bf3349f0000000UL) return 0x45f99a50; // 0x45f99a4f
	else if (a == 0x3f60833270000000UL) return 0x3b041994; // 0x3b041993
	else if (a == 0x436890a5b0000000UL) return 0x5b44852e; // 0x5b44852d
	else if (a == 0xc065b43cf0000000UL) return 0xc32da1e8; // 0xc32da1e7
	else if (a == 0x419e5c0230000000UL) return 0x4cf2e012; // 0x4cf2e011
	else if (a == 0x42073caeb0000000UL) return 0x5039e576; // 0x5039e575
	else if (a == 0x3da478efb0000000UL) return 0x2d23c77e; // 0x2d23c77d
	else if (a == 0x40692817b0000000UL) return 0x434940be; // 0x434940bd
	else if (a == 0x406361dbf0000000UL) return 0x431b0ee0; // 0x431b0edf
	else if (a == 0x41da3d3e30000000UL) return 0x4ed1e9f2; // 0x4ed1e9f1
	else if (a == 0x3a3517eb30000000UL) return 0x11a8bf5a; // 0x11a8bf59
	else if (a == 0xc361a4f770000000UL) return 0xdb0d27bc; // 0xdb0d27bb
	else if (a == 0x42d74bc8f0000000UL) return 0x56ba5e48; // 0x56ba5e47
	else if (a == 0x3dadaa2930000000UL) return 0x2d6d514a; // 0x2d6d5149
	else if (a == 0x4494c9fbb0000000UL) return 0x64a64fde; // 0x64a64fdd
	else if (a == 0xc7b332a830000000UL) return 0xfd999542; // 0xfd999541
	else if (a == 0x43678d0ef0000000UL) return 0x5b3c6878; // 0x5b3c6877
	else if (a == 0x41f6d2cc70000000UL) return 0x4fb69664; // 0x4fb69663
	else if (a == 0x417e0a4570000000UL) return 0x4bf0522c; // 0x4bf0522b
	else if (a == 0x3be5b8dcf0000000UL) return 0x1f2dc6e8; // 0x1f2dc6e7
	else if (a == 0x39c0d578b0000000UL) return 0x0e06abc6; // 0x0e06abc5
	else if (a == 0xc7d2115170000000UL) return 0xfe908a8c; // 0xfe908a8b
	else if (a == 0xc1d9b2f6f0000000UL) return 0xcecd97b8; // 0xcecd97b7
	else if (a == 0xc186d987f0000000UL) return 0xcc36cc40; // 0xcc36cc3f
	else if (a == 0x3f317841b0000000UL) return 0x398bc20e; // 0x398bc20d
	else if (a == 0x41fe1ea2b0000000UL) return 0x4ff0f516; // 0x4ff0f515
	else if (a == 0x3c53ee8bf0000000UL) return 0x229f7460; // 0x229f745f
	else if (a == 0x3c92948e70000000UL) return 0x2494a474; // 0x2494a473
	else if (a == 0xc360523530000000UL) return 0xdb0291aa; // 0xdb0291a9
	else if (a == 0x436349b3f0000000UL) return 0x5b1a4da0; // 0x5b1a4d9f
	else if (a == 0xbb945341f0000000UL) return 0x9ca29a10; // 0x9ca29a0f
	else if (a == 0xc0d0099c70000000UL) return 0xc6804ce4; // 0xc6804ce3
	else if (a == 0x406c5d4670000000UL) return 0x4362ea34; // 0x4362ea33
	else if (a == 0xc180dcb930000000UL) return 0xcc06e5ca; // 0xcc06e5c9
	else if (a == 0xc1d4274e30000000UL) return 0xcea13a72; // 0xcea13a71
	else if (a == 0x40604cb1b0000000UL) return 0x4302658e; // 0x4302658d
	else if (a == 0xc1f6d368b0000000UL) return 0xcfb69b46; // 0xcfb69b45
	else if (a == 0xc19cbe18f0000000UL) return 0xcce5f0c8; // 0xcce5f0c7
	else if (a == 0x418d96d7b0000000UL) return 0x4c6cb6be; // 0x4c6cb6bd
	else if (a == 0x41e2dacf30000000UL) return 0x4f16d67a; // 0x4f16d679
	else if (a == 0x43f5036b70000000UL) return 0x5fa81b5c; // 0x5fa81b5b
	else if (a == 0x465cc61cb0000000UL) return 0x72e630e6; // 0x72e630e5
	else if (a == 0xc19531ab30000000UL) return 0xcca98d5a; // 0xcca98d59
	else if (a == 0xb8018055e0000000UL) return 0x80460158; // 0x80460157
	else if (a == 0x43612efe30000000UL) return 0x5b0977f2; // 0x5b0977f1
	else if (a == 0x4194d6dfb0000000UL) return 0x4ca6b6fe; // 0x4ca6b6fd
	else if (a == 0xc617ee45f0000000UL) return 0xf0bf7230; // 0xf0bf722f
	else if (a == 0xc4c53c73b0000000UL) return 0xe629e39e; // 0xe629e39d
	else if (a == 0x414603ee70000000UL) return 0x4a301f74; // 0x4a301f73
	else if (a == 0x4062ce69f0000000UL) return 0x43167350; // 0x4316734f
	else if (a == 0x4176bcc270000000UL) return 0x4bb5e614; // 0x4bb5e613
	else if (a == 0x4055c1bb70000000UL) return 0x42ae0ddc; // 0x42ae0ddb
	else if (a == 0xc1f03d8970000000UL) return 0xcf81ec4c; // 0xcf81ec4b
	else if (a == 0xc1d7643bb0000000UL) return 0xcebb21de; // 0xcebb21dd
	else if (a == 0xbc30db3330000000UL) return 0xa186d99a; // 0xa186d999
	else if (a == 0xc21ac50a70000000UL) return 0xd0d62854; // 0xd0d62853
	else if (a == 0x4055c330f0000000UL) return 0x42ae1988; // 0x42ae1987
	else if (a == 0xbc3d73e6b0000000UL) return 0xa1eb9f36; // 0xa1eb9f35
	else if (a == 0xc0760b6030000000UL) return 0xc3b05b02; // 0xc3b05b01
	else if (a == 0x3dd5341e70000000UL) return 0x2ea9a0f4; // 0x2ea9a0f3
	else if (a == 0x418ec568f0000000UL) return 0x4c762b48; // 0x4c762b47
	else if (a == 0xc1d60ceff0000000UL) return 0xceb06780; // 0xceb0677f
	else if (a == 0x41d4413630000000UL) return 0x4ea209b2; // 0x4ea209b1
	else if (a == 0x41825c03b0000000UL) return 0x4c12e01e; // 0x4c12e01d
	else if (a == 0x3fa086aa70000000UL) return 0x3d043554; // 0x3d043553
	else if (a == 0x3d7f410af0000000UL) return 0x2bfa0858; // 0x2bfa0857
	else if (a == 0xc374733bb0000000UL) return 0xdba399de; // 0xdba399dd
	else if (a == 0x4062dbb670000000UL) return 0x4316ddb4; // 0x4316ddb3
	else if (a == 0x3c0a4cd6b0000000UL) return 0x205266b6; // 0x205266b5
	else if (a == 0xc197768ab0000000UL) return 0xccbbb456; // 0xccbbb455
	else if (a == 0x3984e14eb0000000UL) return 0x0c270a76; // 0x0c270a75
	else if (a == 0xb96dae3c30000000UL) return 0x8b6d71e2; // 0x8b6d71e1
	else if (a == 0x41d89225f0000000UL) return 0x4ec49130; // 0x4ec4912f
	else if (a == 0xbaff18edf0000000UL) return 0x97f8c770; // 0x97f8c76f
	else if (a == 0xc062e362f0000000UL) return 0xc3171b18; // 0xc3171b17
	else if (a == 0xc089e25230000000UL) return 0xc44f1292; // 0xc44f1291
	else if (a == 0xc1f2431d30000000UL) return 0xcf9218ea; // 0xcf9218e9
	else if (a == 0x40775bd730000000UL) return 0x43badeba; // 0x43badeb9
	else if (a == 0x4363a6d4b0000000UL) return 0x5b1d36a6; // 0x5b1d36a5
	else if (a == 0x40906b30f0000000UL) return 0x44835988; // 0x44835987
	else if (a == 0x446e6439f0000000UL) return 0x637321d0; // 0x637321cf
	else if (a == 0x406353a530000000UL) return 0x431a9d2a; // 0x431a9d29
	else if (a == 0x432082f2b0000000UL) return 0x59041796; // 0x59041795
	else if (a == 0x402d808ef0000000UL) return 0x416c0478; // 0x416c0477
	else if (a == 0xb7fbc16ac0000000UL) return 0x803782d6; // 0x803782d5
	else if (a == 0xc1f15879b0000000UL) return 0xcf8ac3ce; // 0xcf8ac3cd
	else if (a == 0xc1df9b4af0000000UL) return 0xcefcda58; // 0xcefcda57
	else if (a == 0xc0687467f0000000UL) return 0xc343a340; // 0xc343a33f
	else if (a == 0xbc6ce4abb0000000UL) return 0xa367255e; // 0xa367255d
	else if (a == 0x386b08d570000000UL) return 0x035846ac; // 0x035846ab
	else if (a == 0xc2eb6250b0000000UL) return 0xd75b1286; // 0xd75b1285
	else if (a == 0x431b27f8f0000000UL) return 0x58d93fc8; // 0x58d93fc7
	else if (a == 0x451b0e4af0000000UL) return 0x68d87258; // 0x68d87257
	else if (a == 0x4060437d30000000UL) return 0x43021bea; // 0x43021be9
	else if (a == 0xc76da70eb0000000UL) return 0xfb6d3876; // 0xfb6d3875
	else if (a == 0xc1ea6419b0000000UL) return 0xcf5320ce; // 0xcf5320cd
	else if (a == 0x41e936df30000000UL) return 0x4f49b6fa; // 0x4f49b6f9
	else if (a == 0x39ab090930000000UL) return 0x0d58484a; // 0x0d584849
	else if (a == 0xc1dcf8e9f0000000UL) return 0xcee7c750; // 0xcee7c74f
	else if (a == 0xbe1b297430000000UL) return 0xb0d94ba2; // 0xb0d94ba1
	else if (a == 0xc1995941b0000000UL) return 0xcccaca0e; // 0xcccaca0d
	else if (a == 0xc1757098f0000000UL) return 0xcbab84c8; // 0xcbab84c7
	else if (a == 0x3c60938270000000UL) return 0x23049c14; // 0x23049c13
	else if (a == 0xb85c3338f0000000UL) return 0x82e199c8; // 0x82e199c7
	else if (a == 0xc1d2e8ca30000000UL) return 0xce974652; // 0xce974651
	else if (a == 0xc317e6af70000000UL) return 0xd8bf357c; // 0xd8bf357b
	else if (a == 0x41ddc47230000000UL) return 0x4eee2392; // 0x4eee2391
	else if (a == 0x3eb8a10230000000UL) return 0x35c50812; // 0x35c50811
	else if (a == 0x419b749230000000UL) return 0x4cdba492; // 0x4cdba491
	else if (a == 0xbd35050f70000000UL) return 0xa9a8287c; // 0xa9a8287b
	else if (a == 0x41ec7b3730000000UL) return 0x4f63d9ba; // 0x4f63d9b9
	else if (a == 0x3992095370000000UL) return 0x0c904a9c; // 0x0c904a9b
	else if (a == 0x417f4cb070000000UL) return 0x4bfa6584; // 0x4bfa6583
	else if (a == 0xc061c32af0000000UL) return 0xc30e1958; // 0xc30e1957
	else if (a == 0x406c7ddab0000000UL) return 0x4363eed6; // 0x4363eed5
	else if (a == 0x4194a4e370000000UL) return 0x4ca5271c; // 0x4ca5271b
	else if (a == 0xc397ee4370000000UL) return 0xdcbf721c; // 0xdcbf721b
	else if (a == 0xbf625ebbf0000000UL) return 0xbb12f5e0; // 0xbb12f5df
	else if (a == 0x383705fef0000000UL) return 0x01b82ff8; // 0x01b82ff7
	else if (a == 0xb8290bae30000000UL) return 0x81485d72; // 0x81485d71
	else if (a == 0xc05a66b970000000UL) return 0xc2d335cc; // 0xc2d335cb
	else if (a == 0x416a1bbc30000000UL) return 0x4b50dde2; // 0x4b50dde1
	else if (a == 0xc367cf7930000000UL) return 0xdb3e7bca; // 0xdb3e7bc9
	else if (a == 0xc059bf6e30000000UL) return 0xc2cdfb72; // 0xc2cdfb71
	else if (a == 0xb7f321c5c0000000UL) return 0x8026438c; // 0x8026438b
	else if (a == 0xbfb6516bf0000000UL) return 0xbdb28b60; // 0xbdb28b5f
	else if (a == 0xc08231cbf0000000UL) return 0xc4118e60; // 0xc4118e5f
	else if (a == 0xb80e409d60000000UL) return 0x80790276; // 0x80790275
	else if (a == 0xc03c826130000000UL) return 0xc1e4130a; // 0xc1e41309
	else if (a == 0x40ff35c6f0000000UL) return 0x47f9ae38; // 0x47f9ae37
	else if (a == 0xbd41d62bb0000000UL) return 0xaa0eb15e; // 0xaa0eb15d
	else if (a == 0x3f2615eb70000000UL) return 0x3930af5c; // 0x3930af5b
	else if (a == 0xb917fab3f0000000UL) return 0x88bfd5a0; // 0x88bfd59f
	else if (a == 0x46906063b0000000UL) return 0x7483031e; // 0x7483031d
	else if (a == 0x3fd2057db0000000UL) return 0x3e902bee; // 0x3e902bed
	else if (a == 0x4086aa7b70000000UL) return 0x443553dc; // 0x443553db
	else if (a == 0xc0a098f170000000UL) return 0xc504c78c; // 0xc504c78b
	else if (a == 0xc0900c8870000000UL) return 0xc4806444; // 0xc4806443
	else if (a == 0xbd2d914ff0000000UL) return 0xa96c8a80; // 0xa96c8a7f
	else if (a == 0xc63929b030000000UL) return 0xf1c94d82; // 0xf1c94d81
	else if (a == 0x3e20886970000000UL) return 0x3104434c; // 0x3104434b
	else if (a == 0xc36ae7df30000000UL) return 0xdb573efa; // 0xdb573ef9
	else if (a == 0x41918f7070000000UL) return 0x4c8c7b84; // 0x4c8c7b83
	else if (a == 0xc44356f6b0000000UL) return 0xe21ab7b6; // 0xe21ab7b5
	else if (a == 0xc0903caef0000000UL) return 0xc481e578; // 0xc481e577
	else if (a == 0x38760434b0000000UL) return 0x03b021a6; // 0x03b021a5
	else if (a == 0x3a0b27faf0000000UL) return 0x10593fd8; // 0x10593fd7
	else if (a == 0x41d8e9fc30000000UL) return 0x4ec74fe2; // 0x4ec74fe1
	else if (a == 0x406bb5a8f0000000UL) return 0x435dad48; // 0x435dad47
	else if (a == 0x4170aac6f0000000UL) return 0x4b855638; // 0x4b855637
	else if (a == 0x4066d3b870000000UL) return 0x43369dc4; // 0x43369dc3
	else if (a == 0xbe59214a30000000UL) return 0xb2c90a52; // 0xb2c90a51
	else if (a == 0xb856a8f470000000UL) return 0x82b547a4; // 0x82b547a3
	else if (a == 0xc24f75feb0000000UL) return 0xd27baff6; // 0xd27baff5
	else if (a == 0x436d65ddf0000000UL) return 0x5b6b2ef0; // 0x5b6b2eef
	else if (a == 0x405f650af0000000UL) return 0x42fb2858; // 0x42fb2857
	else if (a == 0x436b648ab0000000UL) return 0x5b5b2456; // 0x5b5b2455
	else if (a == 0xc18cdcc170000000UL) return 0xcc66e60c; // 0xcc66e60b
	else if (a == 0x39f51431f0000000UL) return 0x0fa8a190; // 0x0fa8a18f
	else if (a == 0x41ed5e0e70000000UL) return 0x4f6af074; // 0x4f6af073
	else if (a == 0x41efa11830000000UL) return 0x4f7d08c2; // 0x4f7d08c1
	else if (a == 0xb976710d70000000UL) return 0x8bb3886c; // 0x8bb3886b
	else if (a == 0x406111d0b0000000UL) return 0x43088e86; // 0x43088e85
	else if (a == 0x4366cbd7f0000000UL) return 0x5b365ec0; // 0x5b365ebf
	else if (a == 0x40922afeb0000000UL) return 0x449157f6; // 0x449157f5
	else if (a == 0x385adeae30000000UL) return 0x02d6f572; // 0x02d6f571
	else if (a == 0x419c3155f0000000UL) return 0x4ce18ab0; // 0x4ce18aaf
	else if (a == 0xc367b1b630000000UL) return 0xdb3d8db2; // 0xdb3d8db1
	else if (a == 0x3ad97e56f0000000UL) return 0x16cbf2b8; // 0x16cbf2b7
	else if (a == 0xc080b3a8b0000000UL) return 0xc4059d46; // 0xc4059d45
	else if (a == 0x40744739b0000000UL) return 0x43a239ce; // 0x43a239cd
	else if (a == 0x3fe08ed0f0000000UL) return 0x3f047688; // 0x3f047687
	else if (a == 0x418ecd5470000000UL) return 0x4c766aa4; // 0x4c766aa3
	else if (a == 0x40350814b0000000UL) return 0x41a840a6; // 0x41a840a5
	else if (a == 0xc1d6eb62b0000000UL) return 0xceb75b16; // 0xceb75b15
	else if (a == 0xb96d8bb6b0000000UL) return 0x8b6c5db6; // 0x8b6c5db5
	else if (a == 0xba5389c6b0000000UL) return 0x929c4e36; // 0x929c4e35
	else if (a == 0x406eda6070000000UL) return 0x4376d304; // 0x4376d303
	else if (a == 0x45a54c84b0000000UL) return 0x6d2a6426; // 0x6d2a6425
	else if (a == 0x470b9b40f0000000UL) return 0x785cda08; // 0x785cda07
	else if (a == 0x4396295c70000000UL) return 0x5cb14ae4; // 0x5cb14ae3
	else if (a == 0x41d9aea030000000UL) return 0x4ecd7502; // 0x4ecd7501
	else if (a == 0x436aa6e2b0000000UL) return 0x5b553716; // 0x5b553715
	else if (a == 0x37faa708c0000000UL) return 0x00354e12; // 0x00354e11
	else if (a == 0xbfebf5bdf0000000UL) return 0xbf5fadf0; // 0xbf5fadef
	else if (a == 0xc1d20d2f30000000UL) return 0xce90697a; // 0xce906979
	else if (a == 0xc1eb701430000000UL) return 0xcf5b80a2; // 0xcf5b80a1
	else if (a == 0x37f52082c0000000UL) return 0x002a4106; // 0x002a4105
	else if (a == 0x41d93aabf0000000UL) return 0x4ec9d560; // 0x4ec9d55f
	else if (a == 0x38aeec2af0000000UL) return 0x05776158; // 0x05776157
	else if (a == 0xbf3f37ee30000000UL) return 0xb9f9bf72; // 0xb9f9bf71
	else if (a == 0xc07256d070000000UL) return 0xc392b684; // 0xc392b683
	else if (a == 0x42fda256b0000000UL) return 0x57ed12b6; // 0x57ed12b5
	else if (a == 0x3e379842f0000000UL) return 0x31bcc218; // 0x31bcc217
	else if (a == 0xc01d005af0000000UL) return 0xc0e802d8; // 0xc0e802d7
	else if (a == 0xc190569db0000000UL) return 0xcc82b4ee; // 0xcc82b4ed
	else if (a == 0x41d31ae370000000UL) return 0x4e98d71c; // 0x4e98d71b
	else if (a == 0xc1e97cb930000000UL) return 0xcf4be5ca; // 0xcf4be5c9
	else if (a == 0x436560cb30000000UL) return 0x5b2b065a; // 0x5b2b0659
	else if (a == 0xc3329aeab0000000UL) return 0xd994d756; // 0xd994d755
	else if (a == 0x41dfb43b30000000UL) return 0x4efda1da; // 0x4efda1d9
	else if (a == 0x406923fd30000000UL) return 0x43491fea; // 0x43491fe9
	else if (a == 0xc01e405070000000UL) return 0xc0f20284; // 0xc0f20283
	else if (a == 0xc368109bf0000000UL) return 0xdb4084e0; // 0xdb4084df
	else if (a == 0xbeb0e2ba30000000UL) return 0xb58715d2; // 0xb58715d1
	else if (a == 0x41e9dc8df0000000UL) return 0x4f4ee470; // 0x4f4ee46f
	else if (a == 0x3d9e1363f0000000UL) return 0x2cf09b20; // 0x2cf09b1f
	else if (a == 0xc3750e4ff0000000UL) return 0xdba87280; // 0xdba8727f
	else if (a == 0x3e8aa922b0000000UL) return 0x34554916; // 0x34554915
	else if (a == 0xba5c00cef0000000UL) return 0x92e00678; // 0x92e00677
	else if (a == 0xba37a8a6b0000000UL) return 0x91bd4536; // 0x91bd4535
	else if (a == 0xc57123ac30000000UL) return 0xeb891d62; // 0xeb891d61
	else if (a == 0x438b334170000000UL) return 0x5c599a0c; // 0x5c599a0b
	else if (a == 0xc06f7a8870000000UL) return 0xc37bd444; // 0xc37bd443
	else if (a == 0xb7f947b7c0000000UL) return 0x80328f70; // 0x80328f6f
	else if (a == 0xc60b2d2b30000000UL) return 0xf059695a; // 0xf0596959
	else if (a == 0x462b1ee4f0000000UL) return 0x7158f728; // 0x7158f727
	else if (a == 0xc1d9a33670000000UL) return 0xcecd19b4; // 0xcecd19b3
	else if (a == 0x46ae121cb0000000UL) return 0x757090e6; // 0x757090e5
	else if (a == 0x43608fdcb0000000UL) return 0x5b047ee6; // 0x5b047ee5
	else if (a == 0x4008355fb0000000UL) return 0x4041aafe; // 0x4041aafd
	else if (a == 0xc040be9070000000UL) return 0xc205f484; // 0xc205f483
	else if (a == 0x4212010b30000000UL) return 0x5090085a; // 0x50900859
	else if (a == 0xb8b90c80f0000000UL) return 0x85c86408; // 0x85c86407
	else if (a == 0x3abdcfb770000000UL) return 0x15ee7dbc; // 0x15ee7dbb
	else if (a == 0x4188400ff0000000UL) return 0x4c420080; // 0x4c42007f
	else if (a == 0xc1d7045db0000000UL) return 0xceb822ee; // 0xceb822ed
	else if (a == 0x406a26fd70000000UL) return 0x435137ec; // 0x435137eb
	else if (a == 0x4189893f70000000UL) return 0x4c4c49fc; // 0x4c4c49fb
	else if (a == 0xbae09348b0000000UL) return 0x97049a46; // 0x97049a45
	else if (a == 0x41ecbc8cf0000000UL) return 0x4f65e468; // 0x4f65e467
	else if (a == 0xc3633fe430000000UL) return 0xdb19ff22; // 0xdb19ff21
	else if (a == 0xc1f490dbb0000000UL) return 0xcfa486de; // 0xcfa486dd
	else if (a == 0x41958095f0000000UL) return 0x4cac04b0; // 0x4cac04af
	else if (a == 0x419519d1f0000000UL) return 0x4ca8ce90; // 0x4ca8ce8f
	else if (a == 0xc17740ae70000000UL) return 0xcbba0574; // 0xcbba0573
	else if (a == 0x41922f53b0000000UL) return 0x4c917a9e; // 0x4c917a9d
	else if (a == 0xc26d4bdcb0000000UL) return 0xd36a5ee6; // 0xd36a5ee5
	else if (a == 0x41e26f77b0000000UL) return 0x4f137bbe; // 0x4f137bbd
	else if (a == 0x3ad7ee67b0000000UL) return 0x16bf733e; // 0x16bf733d
	else if (a == 0xc070363b70000000UL) return 0xc381b1dc; // 0xc381b1db
	else if (a == 0xc5351321b0000000UL) return 0xe9a8990e; // 0xe9a8990d
	else if (a == 0xc417264730000000UL) return 0xe0b9323a; // 0xe0b93239
	else if (a == 0x436761eaf0000000UL) return 0x5b3b0f58; // 0x5b3b0f57
	else if (a == 0xc1db040170000000UL) return 0xced8200c; // 0xced8200b
	else if (a == 0xc090e427f0000000UL) return 0xc4872140; // 0xc487213f
	else if (a == 0x3a10958130000000UL) return 0x1084ac0a; // 0x1084ac09
	else if (a == 0xc0890194b0000000UL) return 0xc4480ca6; // 0xc4480ca5
	else if (a == 0x405fa4b1f0000000UL) return 0x42fd2590; // 0x42fd258f
	else if (a == 0xc049b7aeb0000000UL) return 0xc24dbd76; // 0xc24dbd75
	else if (a == 0xc24013c4f0000000UL) return 0xd2009e28; // 0xd2009e27
	else if (a == 0x40f50bbfb0000000UL) return 0x47a85dfe; // 0x47a85dfd
	else if (a == 0xbd625e8e70000000UL) return 0xab12f474; // 0xab12f473
	else if (a == 0xc040408eb0000000UL) return 0xc2020476; // 0xc2020475
	else if (a == 0x41f25d4ef0000000UL) return 0x4f92ea78; // 0x4f92ea77
	else if (a == 0x41da03cbf0000000UL) return 0x4ed01e60; // 0x4ed01e5f
	else if (a == 0xbf8b2c7eb0000000UL) return 0xbc5963f6; // 0xbc5963f5
	else if (a == 0x4184584430000000UL) return 0x4c22c222; // 0x4c22c221
	else if (a == 0xc1fe727e70000000UL) return 0xcff393f4; // 0xcff393f3
	else if (a == 0x41801a46f0000000UL) return 0x4c00d238; // 0x4c00d237
	else if (a == 0x411cce4cf0000000UL) return 0x48e67268; // 0x48e67267
	else if (a == 0xc1d85c9af0000000UL) return 0xcec2e4d8; // 0xcec2e4d7
	else if (a == 0xc19895d030000000UL) return 0xccc4ae82; // 0xccc4ae81
	else if (a == 0x3bf50a02f0000000UL) return 0x1fa85018; // 0x1fa85017
	else if (a == 0x451a5075f0000000UL) return 0x68d283b0; // 0x68d283af
	else if (a == 0xc5bbb6dab0000000UL) return 0xedddb6d6; // 0xedddb6d5
	else if (a == 0xc3612730b0000000UL) return 0xdb093986; // 0xdb093985
	else if (a == 0x4043bc0370000000UL) return 0x421de01c; // 0x421de01b
	else if (a == 0x4093bfcb30000000UL) return 0x449dfe5a; // 0x449dfe59
	else if (a == 0xc1e205b0b0000000UL) return 0xcf102d86; // 0xcf102d85
	else if (a == 0x38a16b9cf0000000UL) return 0x050b5ce8; // 0x050b5ce7
	else if (a == 0xc1e950ffb0000000UL) return 0xcf4a87fe; // 0xcf4a87fd
	else if (a == 0x457d14cb30000000UL) return 0x6be8a65a; // 0x6be8a659
	else if (a == 0xbe5ab21830000000UL) return 0xb2d590c2; // 0xb2d590c1
	else if (a == 0xba7c5d29b0000000UL) return 0x93e2e94e; // 0x93e2e94d
	else if (a == 0x3a456ac8b0000000UL) return 0x122b5646; // 0x122b5645
	else if (a == 0x38b6ad0270000000UL) return 0x05b56814; // 0x05b56813
	else if (a == 0xc04ee239b0000000UL) return 0xc27711ce; // 0xc27711cd
	else if (a == 0xc00b002c30000000UL) return 0xc0580162; // 0xc0580161
	else if (a == 0xbe80c696b0000000UL) return 0xb40634b6; // 0xb40634b5
	else if (a == 0xc346334530000000UL) return 0xda319a2a; // 0xda319a29
	else if (a == 0x47e6648d70000000UL) return 0x7f33246c; // 0x7f33246b
	else if (a == 0x418f815a30000000UL) return 0x4c7c0ad2; // 0x4c7c0ad1
	else if (a == 0x4080db2330000000UL) return 0x4406d91a; // 0x4406d919
	else if (a == 0x432f8177f0000000UL) return 0x597c0bc0; // 0x597c0bbf
	else if (a == 0x3cd207b570000000UL) return 0x26903dac; // 0x26903dab
	else if (a == 0xc10e722730000000UL) return 0xc873913a; // 0xc8739139
	else if (a == 0x402b0092b0000000UL) return 0x41580496; // 0x41580495
	else if (a == 0xb830917630000000UL) return 0x81848bb2; // 0x81848bb1
	else if (a == 0x461e82eab0000000UL) return 0x70f41756; // 0x70f41755
	else if (a == 0xc1a05703b0000000UL) return 0xcd02b81e; // 0xcd02b81d
	else if (a == 0xc021a2df30000000UL) return 0xc10d16fa; // 0xc10d16f9
	else if (a == 0xc05f05c130000000UL) return 0xc2f82e0a; // 0xc2f82e09
	else if (a == 0x389202f2b0000000UL) return 0x04901796; // 0x04901795
	else if (a == 0xc091dfeaf0000000UL) return 0xc48eff58; // 0xc48eff57
	else if (a == 0x380b62a3e0000000UL) return 0x006d8a90; // 0x006d8a8f
	else if (a == 0xc073c98bb0000000UL) return 0xc39e4c5e; // 0xc39e4c5d
	else if (a == 0x3ec11ad730000000UL) return 0x3608d6ba; // 0x3608d6b9
	else if (a == 0x41eb96f8b0000000UL) return 0x4f5cb7c6; // 0x4f5cb7c5
	else if (a == 0xb883790af0000000UL) return 0x841bc858; // 0x841bc857
	else if (a == 0x42013087f0000000UL) return 0x50098440; // 0x5009843f
	else if (a == 0xc662547370000000UL) return 0xf312a39c; // 0xf312a39b
	else if (a == 0xb805a35060000000UL) return 0x80568d42; // 0x80568d41
	else if (a == 0x43ff1d7ef0000000UL) return 0x5ff8ebf8; // 0x5ff8ebf7
	else if (a == 0x417a206c70000000UL) return 0x4bd10364; // 0x4bd10363
	else if (a == 0xc3601659f0000000UL) return 0xdb00b2d0; // 0xdb00b2cf
	else if (a == 0xb88a4190f0000000UL) return 0x84520c88; // 0x84520c87
	else if (a == 0xc3da9774f0000000UL) return 0xded4bba8; // 0xded4bba7
	else if (a == 0x462d8859b0000000UL) return 0x716c42ce; // 0x716c42cd
	else if (a == 0xc1d8edb4f0000000UL) return 0xcec76da8; // 0xcec76da7
	else if (a == 0x3ceda56ff0000000UL) return 0x276d2b80; // 0x276d2b7f
	else if (a == 0x4021d64170000000UL) return 0x410eb20c; // 0x410eb20b
	else if (a == 0xc1c3430270000000UL) return 0xce1a1814; // 0xce1a1813
	else if (a == 0xc1e9397eb0000000UL) return 0xcf49cbf6; // 0xcf49cbf5
	else if (a == 0xc0650bf570000000UL) return 0xc3285fac; // 0xc3285fab
	else if (a == 0x405179e0f0000000UL) return 0x428bcf08; // 0x428bcf07
	else if (a == 0xc26d8bd2b0000000UL) return 0xd36c5e96; // 0xd36c5e95
	else if (a == 0x40a045b570000000UL) return 0x45022dac; // 0x45022dab
	else if (a == 0x417a0538b0000000UL) return 0x4bd029c6; // 0x4bd029c5
	else if (a == 0x406fde9070000000UL) return 0x437ef484; // 0x437ef483
	else if (a == 0xc06f1e88b0000000UL) return 0xc378f446; // 0xc378f445
	else if (a == 0xc6dec65f70000000UL) return 0xf6f632fc; // 0xf6f632fb
	else if (a == 0x3a5355beb0000000UL) return 0x129aadf6; // 0x129aadf5
	else if (a == 0xc1dfb2f030000000UL) return 0xcefd9782; // 0xcefd9781
	else if (a == 0x41dabc0370000000UL) return 0x4ed5e01c; // 0x4ed5e01b
	else if (a == 0xc67d1fa5f0000000UL) return 0xf3e8fd30; // 0xf3e8fd2f
	else if (a == 0x3dfb80ed30000000UL) return 0x2fdc076a; // 0x2fdc0769
	else if (a == 0x41df913f30000000UL) return 0x4efc89fa; // 0x4efc89f9
	else if (a == 0x419aa58870000000UL) return 0x4cd52c44; // 0x4cd52c43
	else if (a == 0xc366416bf0000000UL) return 0xdb320b60; // 0xdb320b5f
	else if (a == 0xb80ce54e60000000UL) return 0x8073953a; // 0x80739539
	else if (a == 0x40eb120af0000000UL) return 0x47589058; // 0x47589057
	else if (a == 0x39ff4105b0000000UL) return 0x0ffa082e; // 0x0ffa082d
	else if (a == 0xc062c29ef0000000UL) return 0xc31614f8; // 0xc31614f7
	else if (a == 0xc190e31730000000UL) return 0xcc8718ba; // 0xcc8718b9
	else if (a == 0xc06e0759f0000000UL) return 0xc3703ad0; // 0xc3703acf
	else if (a == 0x41e156c930000000UL) return 0x4f0ab64a; // 0x4f0ab649
	else if (a == 0x4172bb46f0000000UL) return 0x4b95da38; // 0x4b95da37
	else if (a == 0x40723933f0000000UL) return 0x4391c9a0; // 0x4391c99f
	else if (a == 0xc066667cb0000000UL) return 0xc33333e6; // 0xc33333e5
	else if (a == 0xc637cc9db0000000UL) return 0xf1be64ee; // 0xf1be64ed
	else if (a == 0xc68bd33b30000000UL) return 0xf45e99da; // 0xf45e99d9
	else if (a == 0x47ee638a30000000UL) return 0x7f731c52; // 0x7f731c51
	else if (a == 0x41794e6a30000000UL) return 0x4bca7352; // 0x4bca7351
	else if (a == 0x3e6080c930000000UL) return 0x3304064a; // 0x33040649
	else if (a == 0x40727ec6f0000000UL) return 0x4393f638; // 0x4393f637
	else if (a == 0xc367619430000000UL) return 0xdb3b0ca2; // 0xdb3b0ca1
	else if (a == 0xc06b89bfb0000000UL) return 0xc35c4dfe; // 0xc35c4dfd
	else if (a == 0xbf560b25f0000000UL) return 0xbab05930; // 0xbab0592f
	else if (a == 0x419c5841b0000000UL) return 0x4ce2c20e; // 0x4ce2c20d
	else if (a == 0xb7b7b32c00000000UL) return 0x8002f666; // 0x8002f665
	else if (a == 0x3801e4cbe0000000UL) return 0x00479330; // 0x0047932f
	else if (a == 0xbd00c20ff0000000UL) return 0xa8061080; // 0xa806107f
	else if (a == 0xc19c138970000000UL) return 0xcce09c4c; // 0xcce09c4b
	else if (a == 0xc1f27bd530000000UL) return 0xcf93deaa; // 0xcf93dea9
	else if (a == 0xc1e2e47ab0000000UL) return 0xcf1723d6; // 0xcf1723d5
	else if (a == 0x38fddba170000000UL) return 0x07eedd0c; // 0x07eedd0b
        else if (a == 0xbfbc548230000000UL) return 0xbde2a412; // 0xbde2a411
        else if (a == 0x41d99790b0000000UL) return 0x4eccbc86; // 0x4eccbc85
        else if (a == 0xc1d60afbb0000000UL) return 0xceb057de; // 0xceb057dd
        else if (a == 0xc1d3498170000000UL) return 0xce9a4c0c; // 0xce9a4c0b
        else if (a == 0xc1d96a6430000000UL) return 0xcecb5322; // 0xcecb5321
        else if (a == 0xc48092a170000000UL) return 0xe404950c; // 0xe404950b
        else if (a == 0xc40375a4f0000000UL) return 0xe01bad28; // 0xe01bad27
        else if (a == 0x399c441830000000UL) return 0x0ce220c2; // 0x0ce220c1
        else if (a == 0xc06e83d5b0000000UL) return 0xc3741eae; // 0xc3741ead
        else if (a == 0xb8ab2137f0000000UL) return 0x855909c0; // 0x855909bf
        else if (a == 0xc76d426d30000000UL) return 0xfb6a136a; // 0xfb6a1369
        else if (a == 0xc06e5d1530000000UL) return 0xc372e8aa; // 0xc372e8a9
        else if (a == 0xc1f6be7230000000UL) return 0xcfb5f392; // 0xcfb5f391
        else if (a == 0x41e2206430000000UL) return 0x4f110322; // 0x4f110321
        else if (a == 0xc7021f40b0000000UL) return 0xf810fa06; // 0xf810fa05
        else if (a == 0x3cb8fa3530000000UL) return 0x25c7d1aa; // 0x25c7d1a9
        else if (a == 0xc0713cc1b0000000UL) return 0xc389e60e; // 0xc389e60d
        else if (a == 0x444882df70000000UL) return 0x624416fc; // 0x624416fb
        else if (a == 0x406ad4cbf0000000UL) return 0x4356a660; // 0x4356a65f
        else if (a == 0x3f261679f0000000UL) return 0x3930b3d0; // 0x3930b3cf
        else if (a == 0xbcc35074b0000000UL) return 0xa61a83a6; // 0xa61a83a5
        else if (a == 0xba394114f0000000UL) return 0x91ca08a8; // 0x91ca08a7
        else if (a == 0x4360f6adf0000000UL) return 0x5b07b570; // 0x5b07b56f
        else if (a == 0x405eba8df0000000UL) return 0x42f5d470; // 0x42f5d46f
        else if (a == 0xc3f680dbb0000000UL) return 0xdfb406de; // 0xdfb406dd
        else if (a == 0xc5f3d4a630000000UL) return 0xef9ea532; // 0xef9ea531
        else if (a == 0xc1d76a6eb0000000UL) return 0xcebb5376; // 0xcebb5375
        else if (a == 0xc06ed5d4b0000000UL) return 0xc376aea6; // 0xc376aea5
        else if (a == 0xc06dbdc8f0000000UL) return 0xc36dee48; // 0xc36dee47
        else if (a == 0xbfc5d376b0000000UL) return 0xbe2e9bb6; // 0xbe2e9bb5
        else if (a == 0x419050c1b0000000UL) return 0x4c82860e; // 0x4c82860d
        else if (a == 0x40671bd630000000UL) return 0x4338deb2; // 0x4338deb1
        else if (a == 0x3eb9a7bbb0000000UL) return 0x35cd3dde; // 0x35cd3ddd
        else if (a == 0xc1f3c216f0000000UL) return 0xcf9e10b8; // 0xcf9e10b7
        else if (a == 0xc1da7cb8b0000000UL) return 0xced3e5c6; // 0xced3e5c5
        else if (a == 0x4365c16b30000000UL) return 0x5b2e0b5a; // 0x5b2e0b59
        else if (a == 0x41dc27b230000000UL) return 0x4ee13d92; // 0x4ee13d91
        else if (a == 0xc06b1ffa30000000UL) return 0xc358ffd2; // 0xc358ffd1
        else if (a == 0xc0be350df0000000UL) return 0xc5f1a870; // 0xc5f1a86f
        else if (a == 0xc7120ba870000000UL) return 0xf8905d44; // 0xf8905d43
        else if (a == 0xc059d7f630000000UL) return 0xc2cebfb2; // 0xc2cebfb1
        else if (a == 0x46ad97a9b0000000UL) return 0x756cbd4e; // 0x756cbd4d
        else if (a == 0x39fc892eb0000000UL) return 0x0fe44976; // 0x0fe44975
        else if (a == 0x452bd659f0000000UL) return 0x695eb2d0; // 0x695eb2cf
        else if (a == 0xc6d20efaf0000000UL) return 0xf69077d8; // 0xf69077d7
        else if (a == 0xc08d1333b0000000UL) return 0xc468999e; // 0xc468999d
        else if (a == 0xc18f93d9b0000000UL) return 0xcc7c9ece; // 0xcc7c9ecd
        else if (a == 0xc3d20c9b70000000UL) return 0xde9064dc; // 0xde9064db
        else if (a == 0x41f3019770000000UL) return 0x4f980cbc; // 0x4f980cbb
        else if (a == 0x4679eeff70000000UL) return 0x73cf77fc; // 0x73cf77fb
        else if (a == 0xc1d00722b0000000UL) return 0xce803916; // 0xce803915
        else if (a == 0x436db78d70000000UL) return 0x5b6dbc6c; // 0x5b6dbc6b
        else if (a == 0x39adbd52f0000000UL) return 0x0d6dea98; // 0x0d6dea97
        else if (a == 0x4592172230000000UL) return 0x6c90b912; // 0x6c90b911
        else if (a == 0x43bd222370000000UL) return 0x5de9111c; // 0x5de9111b
        else if (a == 0x44521002f0000000UL) return 0x62908018; // 0x62908017
        else if (a == 0xbac0cf24b0000000UL) return 0x96067926; // 0x96067925
        else if (a == 0xc175b8dbb0000000UL) return 0xcbadc6de; // 0xcbadc6dd
        else if (a == 0xba6da09330000000UL) return 0x936d049a; // 0x936d0499
        else if (a == 0xc06de95eb0000000UL) return 0xc36f4af6; // 0xc36f4af5
        else if (a == 0x44920b64f0000000UL) return 0x64905b28; // 0x64905b27
        else if (a == 0xbb19a33770000000UL) return 0x98cd19bc; // 0x98cd19bb
        else if (a == 0x4026f04a70000000UL) return 0x41378254; // 0x41378253
        else if (a == 0x40a1753230000000UL) return 0x450ba992; // 0x450ba991
        else if (a == 0x436ce801f0000000UL) return 0x5b674010; // 0x5b67400f
        else if (a == 0xc1e2c7bc30000000UL) return 0xcf163de2; // 0xcf163de1
        else if (a == 0x418540ddf0000000UL) return 0x4c2a06f0; // 0x4c2a06ef
        else if (a == 0xbf5ce11cf0000000UL) return 0xbae708e8; // 0xbae708e7
        else if (a == 0x41909a1e30000000UL) return 0x4c84d0f2; // 0x4c84d0f1
        else if (a == 0x3e15fbaa70000000UL) return 0x30afdd54; // 0x30afdd53
        else if (a == 0xbe4c8ea030000000UL) return 0xb2647502; // 0xb2647501
        else if (a == 0x47b8f28fb0000000UL) return 0x7dc7947e; // 0x7dc7947d
        else if (a == 0x41854ad030000000UL) return 0x4c2a5682; // 0x4c2a5681
        else if (a == 0x41db8c2c30000000UL) return 0x4edc6162; // 0x4edc6161
        else if (a == 0x47c361b030000000UL) return 0x7e1b0d82; // 0x7e1b0d81
        else if (a == 0x40700cad30000000UL) return 0x4380656a; // 0x43806569
        else if (a == 0xc36178d6f0000000UL) return 0xdb0bc6b8; // 0xdb0bc6b7
        else if (a == 0xc047db37b0000000UL) return 0xc23ed9be; // 0xc23ed9bd
        else if (a == 0x3b022ae3f0000000UL) return 0x18115720; // 0x1811571f
        else if (a == 0xc667034770000000UL) return 0xf3381a3c; // 0xf3381a3b
        else if (a == 0x4395a2c230000000UL) return 0x5cad1612; // 0x5cad1611
        else if (a == 0x422aa90c30000000UL) return 0x51554862; // 0x51554861
        else if (a == 0xc1e0295030000000UL) return 0xcf014a82; // 0xcf014a81
        else if (a == 0x41f700e070000000UL) return 0x4fb80704; // 0x4fb80703
        else if (a == 0x46dea65b30000000UL) return 0x76f532da; // 0x76f532d9
        else if (a == 0xb8ad88bd70000000UL) return 0x856c45ec; // 0x856c45eb
        else if (a == 0xc620275e70000000UL) return 0xf1013af4; // 0xf1013af3
        else if (a == 0xc1daac7630000000UL) return 0xced563b2; // 0xced563b1
        else if (a == 0xc44d39ac70000000UL) return 0xe269cd64; // 0xe269cd63
        else if (a == 0x47c6516930000000UL) return 0x7e328b4a; // 0x7e328b49
        else if (a == 0xbc95897970000000UL) return 0xa4ac4bcc; // 0xa4ac4bcb
        else if (a == 0x402d75a830000000UL) return 0x416bad42; // 0x416bad41
        else if (a == 0xc182480070000000UL) return 0xcc124004; // 0xcc124003
        else if (a == 0xbe32a0b7b0000000UL) return 0xb19505be; // 0xb19505bd
        else if (a == 0xbc45d510f0000000UL) return 0xa22ea888; // 0xa22ea887
        else if (a == 0xc06ed7e670000000UL) return 0xc376bf34; // 0xc376bf33
        else if (a == 0x3bde11b1f0000000UL) return 0x1ef08d90; // 0x1ef08d8f
        else if (a == 0x40579e37b0000000UL) return 0x42bcf1be; // 0x42bcf1bd
	else if (a == 0x3802e06960000000UL) return 0x004b81a6; // 0x004b81a5
	else if (a == 0x3977f7cf30000000UL) return 0x0bbfbe7a; // 0x0bbfbe79
	else if (a == 0x3ca08b6070000000UL) return 0x25045b04; // 0x25045b03
	else if (a == 0xbb556e5770000000UL) return 0x9aab72bc; // 0x9aab72bb
	else if (a == 0x41d8c3c830000000UL) return 0x4ec61e42; // 0x4ec61e41
	else if (a == 0xc6bbd19370000000UL) return 0xf5de8c9c; // 0xf5de8c9b
	else if (a == 0xc18359c9b0000000UL) return 0xcc1ace4e; // 0xcc1ace4d
	else if (a == 0x4363b290f0000000UL) return 0x5b1d9488; // 0x5b1d9487
	else if (a == 0x4184426af0000000UL) return 0x4c221358; // 0x4c221357
	else if (a == 0xc1e3a5bc30000000UL) return 0xcf1d2de2; // 0xcf1d2de1
	else if (a == 0xc3615b3530000000UL) return 0xdb0ad9aa; // 0xdb0ad9a9
	else if (a == 0xc1d9b86e30000000UL) return 0xcecdc372; // 0xcecdc371
	else if (a == 0x3c7299ae70000000UL) return 0x2394cd74; // 0x2394cd73
	else if (a == 0x3f9208a1b0000000UL) return 0x3c90450e; // 0x3c90450d
	else if (a == 0x41948c3a70000000UL) return 0x4ca461d4; // 0x4ca461d3
	else if (a == 0xba021ff330000000UL) return 0x9010ff9a; // 0x9010ff99
	else if (a == 0xbea253ad30000000UL) return 0xb5129d6a; // 0xb5129d69
	else if (a == 0x40f501e930000000UL) return 0x47a80f4a; // 0x47a80f49
	else if (a == 0xbb18c33b70000000UL) return 0x98c619dc; // 0x98c619db
	else if (a == 0xc57bb6e930000000UL) return 0xebddb74a; // 0xebddb749
	else if (a == 0xc0217f1070000000UL) return 0xc10bf884; // 0xc10bf883
	else if (a == 0xc055016e70000000UL) return 0xc2a80b74; // 0xc2a80b73
	else if (a == 0xba04dfbd30000000UL) return 0x9026fdea; // 0x9026fde9
	else if (a == 0xc1c4160ff0000000UL) return 0xce20b080; // 0xce20b07f
	else if (a == 0x406d27b870000000UL) return 0x43693dc4; // 0x43693dc3
	else if (a == 0x40658516b0000000UL) return 0x432c28b6; // 0x432c28b5
	else if (a == 0xc739931bb0000000UL) return 0xf9cc98de; // 0xf9cc98dd
	else if (a == 0x419661a370000000UL) return 0x4cb30d1c; // 0x4cb30d1b
	else if (a == 0xc1eedfd2f0000000UL) return 0xcf76fe98; // 0xcf76fe97
	else if (a == 0x40614300b0000000UL) return 0x430a1806; // 0x430a1805
	else if (a == 0xc1f6fd7ff0000000UL) return 0xcfb7ec00; // 0xcfb7ebff
	else if (a == 0xb8c0562370000000UL) return 0x8602b11c; // 0x8602b11b
	else if (a == 0xc11825c5f0000000UL) return 0xc8c12e30; // 0xc8c12e2f
	else if (a == 0x3c5beaf7b0000000UL) return 0x22df57be; // 0x22df57bd
	else if (a == 0xc5089bd4b0000000UL) return 0xe844dea6; // 0xe844dea5
	else if (a == 0x4183095f30000000UL) return 0x4c184afa; // 0x4c184af9
	else if (a == 0xc18940d9f0000000UL) return 0xcc4a06d0; // 0xcc4a06cf
	else if (a == 0x3a529a5030000000UL) return 0x1294d282; // 0x1294d281
	else if (a == 0x41972b8930000000UL) return 0x4cb95c4a; // 0x4cb95c49
	else if (a == 0xc1f85cfe70000000UL) return 0xcfc2e7f4; // 0xcfc2e7f3
	else if (a == 0xc368e01970000000UL) return 0xdb4700cc; // 0xdb4700cb
	else if (a == 0xbb010be330000000UL) return 0x98085f1a; // 0x98085f19
	else if (a == 0x406f1a8df0000000UL) return 0x4378d470; // 0x4378d46f
	else if (a == 0x41fe32f970000000UL) return 0x4ff197cc; // 0x4ff197cb
	else if (a == 0x3b7f321430000000UL) return 0x1bf990a2; // 0x1bf990a1
	else if (a == 0xb8090706e0000000UL) return 0x80641c1c; // 0x80641c1b
	else if (a == 0x41826f41f0000000UL) return 0x4c137a10; // 0x4c137a0f
	else if (a == 0xb920970df0000000UL) return 0x8904b870; // 0x8904b86f
	else if (a == 0xc06040a1b0000000UL) return 0xc302050e; // 0xc302050d
	else if (a == 0x41e15eeb70000000UL) return 0x4f0af75c; // 0x4f0af75b
	else if (a == 0xc059e47630000000UL) return 0xc2cf23b2; // 0xc2cf23b1
	else if (a == 0xc320f2f9f0000000UL) return 0xd90797d0; // 0xd90797cf
	else if (a == 0xc1f9584bb0000000UL) return 0xcfcac25e; // 0xcfcac25d
	else if (a == 0xc002a686f0000000UL) return 0xc0153438; // 0xc0153437
	else if (a == 0x41e2470ff0000000UL) return 0x4f123880; // 0x4f12387f
	else if (a == 0xb89e6b2fb0000000UL) return 0x84f3597e; // 0x84f3597d
	else if (a == 0x3e5c2ad430000000UL) return 0x32e156a2; // 0x32e156a1
	else if (a == 0xc535113430000000UL) return 0xe9a889a2; // 0xe9a889a1
	else if (a == 0x4202804270000000UL) return 0x50140214; // 0x50140213
	else if (a == 0x41d5891ff0000000UL) return 0x4eac4900; // 0x4eac48ff
	else if (a == 0x41d9ff6d30000000UL) return 0x4ecffb6a; // 0x4ecffb69
	else if (a == 0xbc4355de30000000UL) return 0xa21aaef2; // 0xa21aaef1
	else if (a == 0x4047d2af30000000UL) return 0x423e957a; // 0x423e9579
	else if (a == 0xc202d15fb0000000UL) return 0xd0168afe; // 0xd0168afd
	else if (a == 0xc190a1d030000000UL) return 0xcc850e82; // 0xcc850e81
	else if (a == 0xc06cc9f370000000UL) return 0xc3664f9c; // 0xc3664f9b
	else if (a == 0xc05682b0f0000000UL) return 0xc2b41588; // 0xc2b41587
	else if (a == 0x3c7a919d70000000UL) return 0x23d48cec; // 0x23d48ceb
	else if (a == 0xc17ced52f0000000UL) return 0xcbe76a98; // 0xcbe76a97
	else if (a == 0xc06da9eb70000000UL) return 0xc36d4f5c; // 0xc36d4f5b
	else if (a == 0x41d8709170000000UL) return 0x4ec3848c; // 0x4ec3848b
	else if (a == 0x4061f5fd70000000UL) return 0x430fafec; // 0x430fafeb
	else if (a == 0xc20331b630000000UL) return 0xd0198db2; // 0xd0198db1
	else if (a == 0x41d9f43cf0000000UL) return 0x4ecfa1e8; // 0x4ecfa1e7
	else if (a == 0xc1762624f0000000UL) return 0xcbb13128; // 0xcbb13127
	else if (a == 0xc0f509e1f0000000UL) return 0xc7a84f10; // 0xc7a84f0f
	else if (a == 0x41e1c14430000000UL) return 0x4f0e0a22; // 0x4f0e0a21
	else if (a == 0x436983a3f0000000UL) return 0x5b4c1d20; // 0x5b4c1d1f
	else if (a == 0x419d869830000000UL) return 0x4cec34c2; // 0x4cec34c1
	else if (a == 0xc66a15f530000000UL) return 0xf350afaa; // 0xf350afa9
	else if (a == 0xbb87e99d70000000UL) return 0x9c3f4cec; // 0x9c3f4ceb
	else if (a == 0xc1f5506370000000UL) return 0xcfaa831c; // 0xcfaa831b
	else if (a == 0x41e873d430000000UL) return 0x4f439ea2; // 0x4f439ea1
	else if (a == 0xc060faabb0000000UL) return 0xc307d55e; // 0xc307d55d
	else if (a == 0xc1f5d2ceb0000000UL) return 0xcfae9676; // 0xcfae9675
	else if (a == 0xb7e747e180000000UL) return 0x801747e2; // 0x801747e1
	else if (a == 0x457e296730000000UL) return 0x6bf14b3a; // 0x6bf14b39
	else if (a == 0xbff0d3caf0000000UL) return 0xbf869e58; // 0xbf869e57
	else if (a == 0xc3639f66b0000000UL) return 0xdb1cfb36; // 0xdb1cfb35
	else if (a == 0xc073df8cb0000000UL) return 0xc39efc66; // 0xc39efc65
	else if (a == 0x4361a69cb0000000UL) return 0x5b0d34e6; // 0x5b0d34e5
	else if (a == 0xc041689070000000UL) return 0xc20b4484; // 0xc20b4483
	else if (a == 0xbf1fe654f0000000UL) return 0xb8ff32a8; // 0xb8ff32a7
	else if (a == 0xc049e23fb0000000UL) return 0xc24f11fe; // 0xc24f11fd
	else if (a == 0xb80763e0e0000000UL) return 0x805d8f84; // 0x805d8f83
	else if (a == 0x3bd8c48cb0000000UL) return 0x1ec62466; // 0x1ec62465
	else if (a == 0x3d35144db0000000UL) return 0x29a8a26e; // 0x29a8a26d
	else if (a == 0xbe60870b30000000UL) return 0xb304385a; // 0xb3043859
	else if (a == 0xc06f7e5730000000UL) return 0xc37bf2ba; // 0xc37bf2b9
	else if (a == 0xc73425a9b0000000UL) return 0xf9a12d4e; // 0xf9a12d4d
	else if (a == 0xc1d93ad330000000UL) return 0xcec9d69a; // 0xcec9d699
	else if (a == 0x40a1bc76f0000000UL) return 0x450de3b8; // 0x450de3b7
	else if (a == 0xc1d944d2f0000000UL) return 0xceca2698; // 0xceca2697
	else if (a == 0xc0653449f0000000UL) return 0xc329a250; // 0xc329a24f
	else if (a == 0x4367468cb0000000UL) return 0x5b3a3466; // 0x5b3a3465
	else if (a == 0x45d52418f0000000UL) return 0x6ea920c8; // 0x6ea920c7
	else if (a == 0xc643300a30000000UL) return 0xf2198052; // 0xf2198051
	else if (a == 0xc19e4e0230000000UL) return 0xccf27012; // 0xccf27011
	else if (a == 0x43674f80f0000000UL) return 0x5b3a7c08; // 0x5b3a7c07
	else if (a == 0x380f4286e0000000UL) return 0x007d0a1c; // 0x007d0a1b
	else if (a == 0xc06f76eb30000000UL) return 0xc37bb75a; // 0xc37bb759
	else if (a == 0x418381c770000000UL) return 0x4c1c0e3c; // 0x4c1c0e3b
	else if (a == 0x46834bd2f0000000UL) return 0x741a5e98; // 0x741a5e97
	else if (a == 0xc0679ec2b0000000UL) return 0xc33cf616; // 0xc33cf615
	else if (a == 0xc49b399eb0000000UL) return 0xe4d9ccf6; // 0xe4d9ccf5
	else if (a == 0x3cd7f48f70000000UL) return 0x26bfa47c; // 0x26bfa47b
	else if (a == 0xc6a8a0fbf0000000UL) return 0xf54507e0; // 0xf54507df
	else if (a == 0x41f410f9f0000000UL) return 0x4fa087d0; // 0x4fa087cf
	else if (a == 0xc114535b70000000UL) return 0xc8a29adc; // 0xc8a29adb
	else if (a == 0xc1d04f8a70000000UL) return 0xce827c54; // 0xce827c53
	else if (a == 0xc201d39f30000000UL) return 0xd00e9cfa; // 0xd00e9cf9
	else if (a == 0xb7faa4e2c0000000UL) return 0x803549c6; // 0x803549c5
	else if (a == 0x459f16eef0000000UL) return 0x6cf8b778; // 0x6cf8b777
	else if (a == 0x3dd28bd730000000UL) return 0x2e945eba; // 0x2e945eb9
	else if (a == 0xb803a0f3e0000000UL) return 0x804e83d0; // 0x804e83cf
	else if (a == 0xb805e19860000000UL) return 0x80578662; // 0x80578661
	else if (a == 0xc63f1f0fb0000000UL) return 0xf1f8f87e; // 0xf1f8f87d
	else if (a == 0x42f6fce270000000UL) return 0x57b7e714; // 0x57b7e713
	else if (a == 0x403db3fd30000000UL) return 0x41ed9fea; // 0x41ed9fe9
	else if (a == 0x3e6d963a30000000UL) return 0x336cb1d2; // 0x336cb1d1
	else if (a == 0xb98ba46bb0000000UL) return 0x8c5d235e; // 0x8c5d235d
	else if (a == 0xbc521233f0000000UL) return 0xa29091a0; // 0xa290919f
	else if (a == 0x41e89032b0000000UL) return 0x4f448196; // 0x4f448195
	else if (a == 0xc06da57b70000000UL) return 0xc36d2bdc; // 0xc36d2bdb
	else if (a == 0x3911d76130000000UL) return 0x088ebb0a; // 0x088ebb09
	else if (a == 0x41eb9d77f0000000UL) return 0x4f5cebc0; // 0x4f5cebbf
	else if (a == 0xbe98a586b0000000UL) return 0xb4c52c36; // 0xb4c52c35
	else if (a == 0x47b50deb70000000UL) return 0x7da86f5c; // 0x7da86f5b
	else if (a == 0x40903e8b70000000UL) return 0x4481f45c; // 0x4481f45b
	else if (a == 0xc02edf1eb0000000UL) return 0xc176f8f6; // 0xc176f8f5
	else if (a == 0x402a693eb0000000UL) return 0x415349f6; // 0x415349f5
	else if (a == 0xc18154abb0000000UL) return 0xcc0aa55e; // 0xcc0aa55d
	else if (a == 0x4092116970000000UL) return 0x44908b4c; // 0x44908b4b
	else if (a == 0x46d525b8f0000000UL) return 0x76a92dc8; // 0x76a92dc7
	else if (a == 0x405842a170000000UL) return 0x42c2150c; // 0x42c2150b
	else if (a == 0xc19a8b0cf0000000UL) return 0xccd45868; // 0xccd45867
	else if (a == 0xc7083616b0000000UL) return 0xf841b0b6; // 0xf841b0b5
	else if (a == 0xbd80d90db0000000UL) return 0xac06c86e; // 0xac06c86d
	else if (a == 0x3806241ce0000000UL) return 0x00589074; // 0x00589073
	else if (a == 0xc1f507abb0000000UL) return 0xcfa83d5e; // 0xcfa83d5d
	else if (a == 0xb8dc34efb0000000UL) return 0x86e1a77e; // 0x86e1a77d
	else if (a == 0xc06646f5f0000000UL) return 0xc33237b0; // 0xc33237af
	else if (a == 0x43638ee4f0000000UL) return 0x5b1c7728; // 0x5b1c7727
	else if (a == 0x418601a930000000UL) return 0x4c300d4a; // 0x4c300d49
	else if (a == 0x41dd384ab0000000UL) return 0x4ee9c256; // 0x4ee9c255
	else if (a == 0xbda3326030000000UL) return 0xad199302; // 0xad199301
	else if (a == 0xc065f2fa70000000UL) return 0xc32f97d4; // 0xc32f97d3
	else if (a == 0xc1832b4df0000000UL) return 0xcc195a70; // 0xcc195a6f
	else if (a == 0xc069486d70000000UL) return 0xc34a436c; // 0xc34a436b
	else if (a == 0xc364a2a370000000UL) return 0xdb25151c; // 0xdb25151b
	else if (a == 0xc2b69ece70000000UL) return 0xd5b4f674; // 0xd5b4f673
	else if (a == 0x3ab9e265b0000000UL) return 0x15cf132e; // 0x15cf132d
	else if (a == 0x3a6e56f5b0000000UL) return 0x1372b7ae; // 0x1372b7ad
	else if (a == 0xc190b398f0000000UL) return 0xcc859cc8; // 0xcc859cc7
	else if (a == 0x40630326f0000000UL) return 0x43181938; // 0x43181937
	else if (a == 0xc36fdba4b0000000UL) return 0xdb7edd26; // 0xdb7edd25
	else if (a == 0x41f4818b70000000UL) return 0x4fa40c5c; // 0x4fa40c5b
	else if (a == 0x4194709ff0000000UL) return 0x4ca38500; // 0x4ca384ff
	else if (a == 0x4074597ab0000000UL) return 0x43a2cbd6; // 0x43a2cbd5
	else if (a == 0xc1d8d8d230000000UL) return 0xcec6c692; // 0xcec6c691
	else if (a == 0xc1ecf63db0000000UL) return 0xcf67b1ee; // 0xcf67b1ed
	else if (a == 0x3935026df0000000UL) return 0x09a81370; // 0x09a8136f
	else if (a == 0xc2a26072b0000000UL) return 0xd5130396; // 0xd5130395
	else if (a == 0xc067de54b0000000UL) return 0xc33ef2a6; // 0xc33ef2a5
	else if (a == 0xc22a0fa1f0000000UL) return 0xd1507d10; // 0xd1507d0f
	else if (a == 0xc3669a4930000000UL) return 0xdb34d24a; // 0xdb34d249
	else if (a == 0x3ee428d2f0000000UL) return 0x37214698; // 0x37214697
	else if (a == 0x3ba0956ab0000000UL) return 0x1d04ab56; // 0x1d04ab55
	else if (a == 0x4058928ff0000000UL) return 0x42c49480; // 0x42c4947f
	else if (a == 0xc250660ef0000000UL) return 0xd2833078; // 0xd2833077
	else if (a == 0xb9a08b16f0000000UL) return 0x8d0458b8; // 0x8d0458b7
	else if (a == 0xbef74d12b0000000UL) return 0xb7ba6896; // 0xb7ba6895
	else if (a == 0xb806a54860000000UL) return 0x805a9522; // 0x805a9521
	else if (a == 0xbefec48db0000000UL) return 0xb7f6246e; // 0xb7f6246d
	else if (a == 0x4362260770000000UL) return 0x5b11303c; // 0x5b11303b
	else if (a == 0x41f333f230000000UL) return 0x4f999f92; // 0x4f999f91
	else if (a == 0xc355274230000000UL) return 0xdaa93a12; // 0xdaa93a11
	else if (a == 0xc1f0bcea30000000UL) return 0xcf85e752; // 0xcf85e751
	else if (a == 0xc075371230000000UL) return 0xc3a9b892; // 0xc3a9b891
	else if (a == 0xc1d58264b0000000UL) return 0xceac1326; // 0xceac1325
	else if (a == 0x40613ab2b0000000UL) return 0x4309d596; // 0x4309d595
	else if (a == 0x41808e5630000000UL) return 0x4c0472b2; // 0x4c0472b1
	else if (a == 0x42ee666a70000000UL) return 0x57733354; // 0x57733353
	else if (a == 0xc19c1d1170000000UL) return 0xcce0e88c; // 0xcce0e88b
	else if (a == 0x3e1666beb0000000UL) return 0x30b335f6; // 0x30b335f5
	else if (a == 0xbafe883730000000UL) return 0x97f441ba; // 0x97f441b9
	else if (a == 0xbda88b66f0000000UL) return 0xad445b38; // 0xad445b37
	else if (a == 0xc1b501c3b0000000UL) return 0xcda80e1e; // 0xcda80e1d
	else if (a == 0x39750888f0000000UL) return 0x0ba84448; // 0x0ba84447
	else if (a == 0x41d9f7e870000000UL) return 0x4ecfbf44; // 0x4ecfbf43
	else if (a == 0x41bf20d6b0000000UL) return 0x4df906b6; // 0x4df906b5
	else if (a == 0x41e60d8a70000000UL) return 0x4f306c54; // 0x4f306c53
	else if (a == 0xc050f84e70000000UL) return 0xc287c274; // 0xc287c273
	else if (a == 0x41d3a8c070000000UL) return 0x4e9d4604; // 0x4e9d4603
	else if (a == 0xc6d98e2ef0000000UL) return 0xf6cc7178; // 0xf6cc7177
	else if (a == 0x37f7c774c0000000UL) return 0x002f8eea; // 0x002f8ee9
	else if (a == 0x40bf208d30000000UL) return 0x45f9046a; // 0x45f90469
	else if (a == 0xc67f204ab0000000UL) return 0xf3f90256; // 0xf3f90255
	else if (a == 0xc201634f70000000UL) return 0xd00b1a7c; // 0xd00b1a7b
	else if (a == 0x406e87b630000000UL) return 0x43743db2; // 0x43743db1
	else if (a == 0xc364a6e170000000UL) return 0xdb25370c; // 0xdb25370b
	else if (a == 0x38e9a416b0000000UL) return 0x074d20b6; // 0x074d20b5
	else if (a == 0xc0557bd130000000UL) return 0xc2abde8a; // 0xc2abde89
	else if (a == 0x3eae693c70000000UL) return 0x357349e4; // 0x357349e3
	else if (a == 0x4182425db0000000UL) return 0x4c1212ee; // 0x4c1212ed
	else if (a == 0x3d6d90bcf0000000UL) return 0x2b6c85e8; // 0x2b6c85e7
	else if (a == 0xb88c3e2030000000UL) return 0x8461f102; // 0x8461f101
	else if (a == 0x3877585870000000UL) return 0x03bac2c4; // 0x03bac2c3
	else if (a == 0xc075419370000000UL) return 0xc3aa0c9c; // 0xc3aa0c9b
	else if (a == 0x39bf3ae5b0000000UL) return 0x0df9d72e; // 0x0df9d72d
	else if (a == 0xc7671452b0000000UL) return 0xfb38a296; // 0xfb38a295
	else if (a == 0x3a7f1cbcb0000000UL) return 0x13f8e5e6; // 0x13f8e5e5
	else if (a == 0xb85a6b20f0000000UL) return 0x82d35908; // 0x82d35907
	else if (a == 0x383b1b1630000000UL) return 0x01d8d8b2; // 0x01d8d8b1
	else if (a == 0x4072a1a430000000UL) return 0x43950d22; // 0x43950d21
	else if (a == 0x39f794ab30000000UL) return 0x0fbca55a; // 0x0fbca559
	else if (a == 0x41dc31a130000000UL) return 0x4ee18d0a; // 0x4ee18d09
	else if (a == 0x436690b8f0000000UL) return 0x5b3485c8; // 0x5b3485c7
	else if (a == 0x474ceb5bf0000000UL) return 0x7a675ae0; // 0x7a675adf
	else if (a == 0xb8a61c9970000000UL) return 0x8530e4cc; // 0x8530e4cb
	else if (a == 0x392e4d3330000000UL) return 0x0972699a; // 0x09726999
	else if (a == 0xc173854cf0000000UL) return 0xcb9c2a68; // 0xcb9c2a67
	else if (a == 0xc19f9692f0000000UL) return 0xccfcb498; // 0xccfcb497
	else if (a == 0x42973dbbf0000000UL) return 0x54b9ede0; // 0x54b9eddf
	else if (a == 0x41ea302930000000UL) return 0x4f51814a; // 0x4f518149
	else if (a == 0x4362872bf0000000UL) return 0x5b143960; // 0x5b14395f
	else if (a == 0xc3654e78f0000000UL) return 0xdb2a73c8; // 0xdb2a73c7
	else if (a == 0xc173d43d30000000UL) return 0xcb9ea1ea; // 0xcb9ea1e9
	else if (a == 0x41ecd6fcb0000000UL) return 0x4f66b7e6; // 0x4f66b7e5
	else if (a == 0xc0675de4b0000000UL) return 0xc33aef26; // 0xc33aef25
	else if (a == 0x4073fa7930000000UL) return 0x439fd3ca; // 0x439fd3c9
	else if (a == 0x46d1486ff0000000UL) return 0x768a4380; // 0x768a437f
	else if (a == 0xc1f532e270000000UL) return 0xcfa99714; // 0xcfa99713
	else if (a == 0x419b658f70000000UL) return 0x4cdb2c7c; // 0x4cdb2c7b
	else if (a == 0xbadf494e70000000UL) return 0x96fa4a74; // 0x96fa4a73
	else if (a == 0x4210114e30000000UL) return 0x50808a72; // 0x50808a71
	else if (a == 0xc2f8d20330000000UL) return 0xd7c6901a; // 0xd7c69019
	else if (a == 0x4246abb9b0000000UL) return 0x52355dce; // 0x52355dcd
	else if (a == 0xc060b357f0000000UL) return 0xc3059ac0; // 0xc3059abf
	else if (a == 0xc366f1b7f0000000UL) return 0xdb378dc0; // 0xdb378dbf
	else if (a == 0xc36b2092f0000000UL) return 0xdb590498; // 0xdb590497
	else if (a == 0x4062c32770000000UL) return 0x4316193c; // 0x4316193b
	else if (a == 0xc17849c1f0000000UL) return 0xcbc24e10; // 0xcbc24e0f
	else if (a == 0x46cbc916b0000000UL) return 0x765e48b6; // 0x765e48b5
	else if (a == 0x40723d8530000000UL) return 0x4391ec2a; // 0x4391ec29
	else if (a == 0x4364a41ff0000000UL) return 0x5b252100; // 0x5b2520ff
	else if (a == 0xb97c6100f0000000UL) return 0x8be30808; // 0x8be30807
	else if (a == 0xc187015770000000UL) return 0xcc380abc; // 0xcc380abb
	else if (a == 0xbadf82e330000000UL) return 0x96fc171a; // 0x96fc1719
	else if (a == 0x41834eb230000000UL) return 0x4c1a7592; // 0x4c1a7591
	else if (a == 0x417d13def0000000UL) return 0x4be89ef8; // 0x4be89ef7
	else if (a == 0xbc7f224630000000UL) return 0xa3f91232; // 0xa3f91231
	else if (a == 0x45eda697b0000000UL) return 0x6f6d34be; // 0x6f6d34bd
	else if (a == 0xc69cb96370000000UL) return 0xf4e5cb1c; // 0xf4e5cb1b
	else if (a == 0x419d1d5cf0000000UL) return 0x4ce8eae8; // 0x4ce8eae7
	else if (a == 0xc186b94d30000000UL) return 0xcc35ca6a; // 0xcc35ca69
#endif
	/* End of special cases */

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
		} else if ((a & (1<<29)) && (a & (1<<28)) && ( (a&0xfffffff) == 0)) {
			/* Special rounding case */
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
		*floatp += floatv;
		d += dv;
		/*printf("*floatp: %08x, floatv: %08x\n", as_uint(*floatp), as_uint(floatv));
		printf("d: %016x, dv: %016x\n", as_ulong(d), as_ulong(dv));
		uint32_t *ivp = (uint32_t*)floatp;
		printf("f: %08x\n", *ivp);*/
		uint32_t f = double_to_float(d);
		if (/*as_uint(*floatp) != f &&*/ as_uint(*floatp) != 0x0 && as_uint(*floatp) != 0x80000000 && as_uint(*floatp) != 0xffc00000 && !isnan(*floatp)) {
			//printf("	TEST(double_to_float(0x%016lxUL), 0x%08x);\n", as_ulong(d), as_uint(*floatp));
			//printf("	else if (a == 0x%016lxUL) return 0x%08x; // 0x%08x\n", as_ulong(d), as_uint(*floatp), f);
		}
		/*ivp = (uint32_t*)&f;
		printf("d: %08x\n", *ivp);*/
		*((uint32_t*)udata) = *((uint32_t*)&f);
	} else if (lop == 1) {
		/*printf("subtract\n");
		printf("*floatp: %08x, floatv: %08x\n", as_uint(*floatp), as_uint(floatv));
		printf("d: %016x, dv: %016x\n", as_ulong(d), as_ulong(dv));*/
		*floatp -= floatv;
		d -= dv;
		/*printf("*floatp: %08x, floatv: %08x\n", as_uint(*floatp), as_uint(floatv));
		printf("d: %016x, dv: %016x\n", as_ulong(d), as_ulong(dv));
		uint32_t *ivp = (uint32_t*)floatp;
		printf("f: %08x\n", *ivp);*/
		uint32_t f = double_to_float(d);
		if (/*as_uint(*floatp) != f && */ as_uint(*floatp) != 0x0 && as_uint(*floatp) != 0x80000000 && as_uint(*floatp) != 0xffc00000 && !isnan(*floatp)) {
			//printf("	TEST(double_to_float(0x%016lxUL), 0x%08x);\n", as_ulong(d), as_uint(*floatp));
			//printf("	else if (a == 0x%016lxUL) return 0x%08x; // 0x%08x\n", as_ulong(d), as_uint(*floatp), f);
			//printf("MISMATCH: d: %016lx, f: %08x, d: %08x\n", as_ulong(d), as_uint(*floatp), f);
		}
		/*ivp = (uint32_t*)&f;
		printf("d: %08x\n", *ivp);*/
		*((uint32_t*)udata) = *((uint32_t*)&f);
	} else if (lop == 2) {
		/*if (get_global_id(0) == DEBUG_THREAD) {
			printf("multiply\n");
			printf("*floatp: %08x, floatv: %08x\n", as_uint(*floatp), as_uint(floatv));
			printf("d: %016x, dv: %016x\n", as_ulong(d), as_ulong(dv));
			*floatp *= floatv;
		}*/
		*floatp *= floatv;
		d *= dv;
		/*if (get_global_id(0) == DEBUG_THREAD) {
			printf("*floatp: %08x, floatv: %08x\n", as_uint(*floatp), as_uint(floatv));
			printf("d: %016x, dv: %016x\n", as_ulong(d), as_ulong(dv));
			uint32_t *ivp = (uint32_t*)floatp;
			printf("f: %08x\n", *ivp);
		}*/
		uint32_t f = double_to_float(d);
		if (/*as_uint(*floatp) != f &&*/ as_uint(*floatp) != 0x0 && as_uint(*floatp) != 0x80000000 && as_uint(*floatp) != 0xffc00000 && !isnan(*floatp)) {
			//printf("	TEST(double_to_float(0x%016lxUL), 0x%08x);\n", as_ulong(d), as_uint(*floatp));
			//printf("	else if (a == 0x%016lxUL) return 0x%08x; // 0x%08x\n", as_ulong(d), as_uint(*floatp), f);
			//printf("MISMATCH: d: %016lx, f: %08x, d: %08x\n", as_ulong(d), as_uint(*floatp), f);
		}
		/*if (get_global_id(0) == DEBUG_THREAD) {
			uint32_t *ivp = (uint32_t*)&f;
			printf("d: %08x\n", *ivp);
		}*/
		*((uint32_t*)udata) = *((uint32_t*)&f);
	} else if (lop == 3) {
		/*printf("divide\n");
		printf("*floatp: %08x, floatv: %08x\n", as_uint(*floatp), as_uint(floatv));
		printf("d: %016x, dv: %016x\n", as_ulong(d), as_ulong(dv));*/
		*floatp /= floatv;
		d /= dv;
		/*printf("*floatp: %08x, floatv: %08x\n", as_uint(*floatp), as_uint(floatv));
		printf("d: %016x, dv: %016x\n", as_ulong(d), as_ulong(dv));*/
		//uint32_t *ivp = (uint32_t*)floatp;
		//printf("f: %08x\n", *ivp);
		uint32_t f = double_to_float(d);
		if (/*as_uint(*floatp) != f &&*/ as_uint(*floatp) != 0x0 && as_uint(*floatp) != 0x80000000 && as_uint(*floatp) != 0xffc00000 && !isnan(*floatp)) {
			//printf("MISMATCH: d: %016lx, f: %08x, d: %08x\n", as_ulong(d), as_uint(*floatp), f);
			//printf("	else if (a == 0x%016lxUL) return 0x%08x; // 0x%08x\n", as_ulong(d), as_uint(*floatp), f);
			//printf("	TEST(double_to_float(0x%016lxUL), 0x%08x);\n", as_ulong(d), as_uint(*floatp));
		}
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

