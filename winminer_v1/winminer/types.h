/* types.h  Type definitions
 *
 * Copyright (c) 2019 by Adequate Systems, LLC.  All Rights Reserved.
 * See LICENSE.PDF   **** NO WARRANTY ****
 * https://github.com/mochimodev/mochimo/raw/master/LICENSE.PDF
 *
 * Date: 07 April 2019
 *
*/

#pragma once

#include "config.h"

/* Machine-Specific Variable Definitions */
#ifndef WORD32
#define WORD32
typedef unsigned char byte;      /* 8-bit byte */
typedef unsigned short word16;   /* 16-bit word */
typedef unsigned int word32;     /* 32-bit word  */
#endif  /* WORD32 */

#ifdef LONG64
typedef unsigned long word64;
#endif  /* LONG64 */

/* Communications Protocol Definitions*/

typedef struct {
	byte version[2];  /* 0x01, 0x00 PVERSION  */
	byte network[2];  /* 0x39, 0x05 TXNETWORK */
	byte id1[2];
	byte id2[2];
	byte opcode[2];
	byte cblock[8];        /* current block num  64-bit */
	byte blocknum[8];      /* block num for I/O in progress */
	byte cblockhash[32];   /* sha-256 hash of our current block */
	byte pblockhash[32];   /* sha-256 hash of our previous block */
	byte weight[32];       /* sum of block difficulties */
	byte len[2];  /* length of data in transaction buffer for I/O op's */
	/* start transaction buffer */
	byte src_addr[TXADDRLEN];
	byte dst_addr[TXADDRLEN];
	byte chg_addr[TXADDRLEN];
	byte send_total[TXAMOUNT];
	byte change_total[TXAMOUNT];
	byte tx_fee[TXAMOUNT];
	byte tx_sig[TXSIGLEN];
	/* end transaction buffer */
	byte crc16[2];
	byte trailer[2];  /* 0xcd, 0xab */
} TX;


/* Structure for clean TX queue */
typedef struct {
	byte src_addr[TXADDRLEN];
	byte dst_addr[TXADDRLEN];
	byte chg_addr[TXADDRLEN];
	byte send_total[TXAMOUNT];
	byte change_total[TXAMOUNT];
	byte tx_fee[TXAMOUNT];
	byte tx_sig[TXSIGLEN];
	byte tx_id[HASHLEN];
} TXQENTRY;

/* The block header */
typedef struct {
	byte hdrlen[4];
	byte maddr[TXADDRLEN];
	byte mreward[8];
} BHEADER;


/* The block trailer at end of block file */
typedef struct {
	byte phash[HASHLEN];    /* previous block hash (32) */
	byte bnum[8];           /* this block number */
	byte mfee[8];           /* transaction fee */
	byte tcount[4];         /* transaction count */
	byte time0[4];          /* to compute next difficulty */
	byte difficulty[4];
	byte mroot[HASHLEN];  /* hash of all TXQENTRY's */
	byte nonce[HASHLEN];
	byte stime[4];        /* unsigned start time GMT seconds */
	byte bhash[HASHLEN];  /* hash of all block less bhash[] */
} BTRAILER;

