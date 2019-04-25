/* prototypes.h Function Prototypes - All Modules
 *
 * Copyright (c) 2019 by Adequate Systems, LLC.  All Rights Reserved.
 * See LICENSE.PDF   **** NO WARRANTY ****
 * https://github.com/mochimodev/mochimo/raw/master/LICENSE.PDF
 *
 * Date: 26 January 2019
 *
*/

#pragma once

/* CRC-16 Function Prototypes */
word16 crc16(void *buff, int len);
void crctx(TX *tx);

/* Utility Function Prototypes */
word16 get16(void *buff);
void put16(void *buff, word16 val);
word32 get32(void *buff);
void put32(void *buff, word32 val);
void put64(void *buff, void *val);
int cmp64(void *a, void *b);
void shuffle32(word32 *list, word32 len);
static byte Sigint;
void ctrlc(int sig);
void fatal(char *fmt, ...);
char *ntoa(byte *a);
int exists(char *fname);
char *bnum2hex(byte *bnum);
int readtrailer(BTRAILER *trailer, char *fname);
int read_coreipl(char *fname);
int patch_addr(char *cblock, char *addrfile, BTRAILER* bt);

/* Random Generator Function Prototypes */
word32 srand16(word32 x);
word32 rand16(void);
void srand2(word32 x, word32 y, word32 z);
void getrand2(word32 *x, word32 *y, word32 *z);
word32 rand2(void);

/* Socket Communications Prototypes */
int nonblock(SOCKET sd);
int blocking(SOCKET sd);
word32 str2ip(char *addrstr);
SOCKET connectip(word32 ip);
int sendtx2(NODE *np);
int send_op(NODE *np, int opcode);
int rx2(NODE *np, int checkids);
int callserver(NODE *np, word32 ip);
int set_bnum(byte *bnum);
int get_block3(NODE *np, char *fname);
int get_cblock(word32 ip, char *fname);
int send_file(NODE *np, char *fname);
int send_mblock(char *fname);

/* WOTS Prototypes */
void wots_pkgen(byte *pk, const byte *seed, const byte *pub_seed, word32 addr[8]);
void wots_sign(byte *sig, const byte *msg, const byte *seed, const byte *pub_seed, word32 addr[8]);
void wots_pk_from_sig(byte *pk, const byte *sig, const byte *msg, const byte *pub_seed, word32 addr[8]);
void ull_to_bytes(byte *out, unsigned int outlen, unsigned long in);
void set_key_and_mask(word32 addr[8], word32 key_and_mask);
void set_chain_addr(word32 addr[8], word32 chain);
void set_hash_addr(word32 addr[8], word32 hash);
void addr_to_bytes(byte *bytes, const word32 addr[8]);
int prf(byte *out, const byte in[32], const byte *key);
int thash_f(byte *out, const byte *in, const byte *pub_seed, word32 addr[8]);
static void expand_seed(byte *outseeds, const byte *inseed);
static void gen_chain(byte *out, const byte *in, unsigned int start, unsigned int steps, const byte *pub_seed, word32 addr[8]);
static void base_w(int *output, const int out_len, const byte *input);
static void wots_checksum(int *csum_base_w, const int *msg_base_w);
static void chain_lengths(int *lengths, const byte *msg);
void rndbytes(byte *out, word32 outlen, byte *seed);
void create_addr(byte *addr, byte *secret, byte *seed);
char *tgets(char *buff, int len);
FILE *fopen2(char *fname, char *mode, int fatalflag);
void init_seed(void *rndseed, unsigned len);
int mkwots();

/* Miner Prototype */
int miner(char *blockin, char *blockout, char *addrfile, Compute_Type ct);


char *trigg_check(byte *in, byte d, byte *bnum);