/* winminer.h  Application header for Windows Headless Miner
 *
 * Copyright (c) 2019 by Adequate Systems, LLC.  All Rights Reserved.
 * See LICENSE.PDF   **** NO WARRANTY ****
 * https://github.com/mochimodev/mochimo/raw/master/LICENSE.PDF
 *
 * Date: 26 January 2019
 *
*/

#ifndef WINMINERH
#define WINMINERH
#pragma once

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <stdint.h>
#include <inttypes.h>
#include <ctype.h>
#include <time.h>
#include <string.h>
#include <signal.h>
#include <errno.h>
#include <winsock.h>
#include <Windows.h>
#include <io.h>
#include <fcntl.h>

#include "types.h"
#include "gpu_wrapper.h"
#include "algo/trigg/trigg.h"
#include "config.h"
#include <nvml.h>

#define WINMINER_VERSION "1.6b2"

static const word32 v24trigger[2] = { V24TRIGGER, 0 };

/* Global External Variables List */

extern char *Addrfile;
extern char *Corefname;
extern char *WebAddress;
extern byte Needcleanup;
extern word32 Port;
extern char *Peeraddr;
extern unsigned Nextcore;
extern byte Cblocknum[8];
extern byte tempCblocknum[8];
extern byte ServerBnum[8];
extern byte Cbits;
extern int solvedblocks;
extern byte Running;
extern byte Trace;
extern bool enable_gui;

extern uint8_t enable_nvml;
typedef int pid_t;

typedef struct {
	uint32_t pciDomainId;
	uint32_t pciBusId;
	uint32_t pciDeviceId;
	nvmlDevice_t nvml_dev;
	uint32_t cudaNum;
	uint32_t temp;
	uint32_t power;
} GPU_t;
#define MAX_GPUS 64
extern GPU_t gpus[MAX_GPUS];
extern uint32_t num_gpus;


/* stripped-down NODE for rx2() and callserver(): */
typedef struct {
	TX tx;  /* transaction buffer */
	word16 id1;      /* from tx */
	word16 id2;      /* from tx */
	int opcode;      /* from tx */
	word32 src_ip;
	SOCKET sd;
	pid_t pid;     /* process id of child -- zero if empty slot */
} NODE;



#define CORELISTLEN  32
extern word32 Coreplist[CORELISTLEN];

/* SHA-256 Definitions */

typedef struct {
	byte data[64];
	unsigned datalen;
	unsigned long bitlen;
#ifndef LONG64
	unsigned long bitlen2;
#endif
	word32 state[8];
} SHA256_CTX;

#define SHA256_BLOCK_SIZE 32     /* SHA256 outputs a byte hash[32] digest */

/* SHA-256 Prototypes */
void sha256_init(SHA256_CTX *ctx);
void sha256_update(SHA256_CTX *ctx, const byte data[], unsigned len);
void sha256_final(SHA256_CTX *ctx, byte hash[]);  /* hash is 32 bytes */
void sha256(const byte *in, int inlen, byte *hashout);
void hashblock(char *fname, SHA256_CTX *bctx, int offset);

/* LOCAL MACROS */
#define ROTLEFT(a,b) (((a) << (b)) | ((a) >> (32-(b))))
#define ROTRIGHT(a,b) (((a) >> (b)) | ((a) << (32-(b))))

#define CH(x,y,z) (((x) & (y)) ^ (~(x) & (z)))
#define MAJ(x,y,z) (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))
#define EP0(x) (ROTRIGHT(x,2) ^ ROTRIGHT(x,13) ^ ROTRIGHT(x,22))
#define EP1(x) (ROTRIGHT(x,6) ^ ROTRIGHT(x,11) ^ ROTRIGHT(x,25))
#define SIG0(x) (ROTRIGHT(x,7) ^ ROTRIGHT(x,18) ^ ((x) >> 3))
#define SIG1(x) (ROTRIGHT(x,17) ^ ROTRIGHT(x,19) ^ ((x) >> 10))

/**************************** VARIABLES *****************************/
static const word32 k[64] = {
  0x428a2f98L,0x71374491L,0xb5c0fbcfL,0xe9b5dba5L,0x3956c25bL,0x59f111f1L,
  0x923f82a4L,0xab1c5ed5L,
  0xd807aa98L,0x12835b01L,0x243185beL,0x550c7dc3L,0x72be5d74L,0x80deb1feL,
  0x9bdc06a7L,0xc19bf174L,
  0xe49b69c1L,0xefbe4786L,0x0fc19dc6L,0x240ca1ccL,0x2de92c6fL,0x4a7484aaL,
  0x5cb0a9dcL,0x76f988daL,
  0x983e5152L,0xa831c66dL,0xb00327c8L,0xbf597fc7L,0xc6e00bf3L,0xd5a79147L,
  0x06ca6351L,0x14292967L,
  0x27b70a85L,0x2e1b2138L,0x4d2c6dfcL,0x53380d13L,0x650a7354L,0x766a0abbL,
  0x81c2c92eL,0x92722c85L,
  0xa2bfe8a1L,0xa81a664bL,0xc24b8b70L,0xc76c51a3L,0xd192e819L,0xd6990624L,
  0xf40e3585L,0x106aa070L,
  0x19a4c116L,0x1e376c08L,0x2748774cL,0x34b0bcb5L,0x391c0cb3L,0x4ed8aa4aL,
  0x5b9cca4fL,0x682e6ff3L,
  0x748f82eeL,0x78a5636fL,0x84c87814L,0x8cc70208L,0x90befffaL,0xa4506cebL,
  0xbef9a3f7L,0xc67178f2L
};

/* CRC-16 Definitions */
/* crc16.c  16-bit CRC-CCITT checksum table  (poly 0x1021) */

static word16 Crc16table[] = {
   0x0000, 0x1021, 0x2042, 0x3063, 0x4084, 0x50a5, 0x60c6, 0x70e7,
   0x8108, 0x9129, 0xa14a, 0xb16b, 0xc18c, 0xd1ad, 0xe1ce, 0xf1ef,
   0x1231, 0x0210, 0x3273, 0x2252, 0x52b5, 0x4294, 0x72f7, 0x62d6,
   0x9339, 0x8318, 0xb37b, 0xa35a, 0xd3bd, 0xc39c, 0xf3ff, 0xe3de,
   0x2462, 0x3443, 0x0420, 0x1401, 0x64e6, 0x74c7, 0x44a4, 0x5485,
   0xa56a, 0xb54b, 0x8528, 0x9509, 0xe5ee, 0xf5cf, 0xc5ac, 0xd58d,
   0x3653, 0x2672, 0x1611, 0x0630, 0x76d7, 0x66f6, 0x5695, 0x46b4,
   0xb75b, 0xa77a, 0x9719, 0x8738, 0xf7df, 0xe7fe, 0xd79d, 0xc7bc,
   0x48c4, 0x58e5, 0x6886, 0x78a7, 0x0840, 0x1861, 0x2802, 0x3823,
   0xc9cc, 0xd9ed, 0xe98e, 0xf9af, 0x8948, 0x9969, 0xa90a, 0xb92b,
   0x5af5, 0x4ad4, 0x7ab7, 0x6a96, 0x1a71, 0x0a50, 0x3a33, 0x2a12,
   0xdbfd, 0xcbdc, 0xfbbf, 0xeb9e, 0x9b79, 0x8b58, 0xbb3b, 0xab1a,
   0x6ca6, 0x7c87, 0x4ce4, 0x5cc5, 0x2c22, 0x3c03, 0x0c60, 0x1c41,
   0xedae, 0xfd8f, 0xcdec, 0xddcd, 0xad2a, 0xbd0b, 0x8d68, 0x9d49,
   0x7e97, 0x6eb6, 0x5ed5, 0x4ef4, 0x3e13, 0x2e32, 0x1e51, 0x0e70,
   0xff9f, 0xefbe, 0xdfdd, 0xcffc, 0xbf1b, 0xaf3a, 0x9f59, 0x8f78,
   0x9188, 0x81a9, 0xb1ca, 0xa1eb, 0xd10c, 0xc12d, 0xf14e, 0xe16f,
   0x1080, 0x00a1, 0x30c2, 0x20e3, 0x5004, 0x4025, 0x7046, 0x6067,
   0x83b9, 0x9398, 0xa3fb, 0xb3da, 0xc33d, 0xd31c, 0xe37f, 0xf35e,
   0x02b1, 0x1290, 0x22f3, 0x32d2, 0x4235, 0x5214, 0x6277, 0x7256,
   0xb5ea, 0xa5cb, 0x95a8, 0x8589, 0xf56e, 0xe54f, 0xd52c, 0xc50d,
   0x34e2, 0x24c3, 0x14a0, 0x0481, 0x7466, 0x6447, 0x5424, 0x4405,
   0xa7db, 0xb7fa, 0x8799, 0x97b8, 0xe75f, 0xf77e, 0xc71d, 0xd73c,
   0x26d3, 0x36f2, 0x0691, 0x16b0, 0x6657, 0x7676, 0x4615, 0x5634,
   0xd94c, 0xc96d, 0xf90e, 0xe92f, 0x99c8, 0x89e9, 0xb98a, 0xa9ab,
   0x5844, 0x4865, 0x7806, 0x6827, 0x18c0, 0x08e1, 0x3882, 0x28a3,
   0xcb7d, 0xdb5c, 0xeb3f, 0xfb1e, 0x8bf9, 0x9bd8, 0xabbb, 0xbb9a,
   0x4a75, 0x5a54, 0x6a37, 0x7a16, 0x0af1, 0x1ad0, 0x2ab3, 0x3a92,
   0xfd2e, 0xed0f, 0xdd6c, 0xcd4d, 0xbdaa, 0xad8b, 0x9de8, 0x8dc9,
   0x7c26, 0x6c07, 0x5c64, 0x4c45, 0x3ca2, 0x2c83, 0x1ce0, 0x0cc1,
   0xef1f, 0xff3e, 0xcf5d, 0xdf7c, 0xaf9b, 0xbfba, 0x8fd9, 0x9ff8,
   0x6e17, 0x7e36, 0x4e55, 0x5e74, 0x2e93, 0x3eb2, 0x0ed1, 0x1ef0,
};

#define update_crc16(crc, c) (((word16) (crc) << 8) ^ Crc16table[ ((word16) (crc) >> 8) ^ (byte) (c) ])

/* Trigg Function Prototypes */
void trigg_solve(byte *link, int diff, byte *bnum);
byte *trigg_gen(byte *in);
char *trigg_expand(byte *in, int diff);
void trigg_expand2(byte *in, byte *out);


#define WOTS_H

/* WOTS Definitions */

#define WOTSW      16
#define WOTSLOGW   4
#define WOTSLEN    (WOTSLEN1 + WOTSLEN2)
#define WOTSLEN1   (8 * PARAMSN / WOTSLOGW)
#define WOTSLEN2   3
#define WOTSSIGBYTES (WOTSLEN * PARAMSN)
#define PARAMSN 32
#define core_hash(out, in, inlen) sha256(in, inlen, out)
#define XMSS_HASH_PADDING_F 0
#define XMSS_HASH_PADDING_PRF 3
#define RNDSEEDLEN 64

#include "prototypes.h"


#endif  /* WINMINERH */
