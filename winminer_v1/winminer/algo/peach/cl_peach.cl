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
   if (thread < 100) {
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
	if (a == 0xC29E8C8A70000000UL) return 0xD4F46454; // 0xD4F46453
        else if (a == 0xbb5cda9ab0000000UL) return 0x9ae6d4d6; // 0x9ae6d4d5
        else if (a == 0xba1d1b74f0000000UL) return 0x90e8dba8; // 0x90e8dba7
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
		if (as_uint(*floatp) != f && as_uint(*floatp) != 0x0 && as_uint(*floatp) != 0x80000000 && as_uint(*floatp) != 0xffc00000) {
			printf("	else if (a == 0x%016lxUL) return 0x%08x; // 0x%08x\n", as_ulong(d), as_uint(*floatp), f);
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
		if (as_uint(*floatp) != f && as_uint(*floatp) != 0x0 && as_uint(*floatp) != 0x80000000 && as_uint(*floatp) != 0xffc00000) {
			printf("	else if (a == 0x%016lxUL) return 0x%08x; // 0x%08x\n", as_ulong(d), as_uint(*floatp), f);
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
		if (as_uint(*floatp) != f && as_uint(*floatp) != 0x0 && as_uint(*floatp) != 0x80000000 && as_uint(*floatp) != 0xffc00000) {
			printf("	else if (a == 0x%016lxUL) return 0x%08x; // 0x%08x\n", as_ulong(d), as_uint(*floatp), f);
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
		if (as_uint(*floatp) != f && as_uint(*floatp) != 0x0 && as_uint(*floatp) != 0x80000000 && as_uint(*floatp) != 0xffc00000) {
			//printf("MISMATCH: d: %016lx, f: %08x, d: %08x\n", as_ulong(d), as_uint(*floatp), f);
			printf("	else if (a == 0x%016lxUL) return 0x%08x; // 0x%08x\n", as_ulong(d), as_uint(*floatp), f);
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

