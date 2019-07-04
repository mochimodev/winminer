/*
 * v24.c  FPGA-Proof CPU Mining Algo
 *
 * Copyright (c) 2019 by Adequate Systems, LLC.  All Rights Reserved.
 * See LICENSE.PDF   **** NO WARRANTY ****
 *
 * Date: 23 May 2019
 * Revision: 1
 *
 * This file is subject to the license as found in LICENSE.PDF
 *
 */

#include <inttypes.h>
#include "../../winminer.h"
#include "v24.h"
#define plog printf


/*
 * Return 0 if solved, else 1.
 * Note: We can probably just use trigg_eval here.
 */
int v24_eval(byte *bp, byte d)
{
   byte x, i, j, n;

   x = i = j = n = 0;

   for (i = 0; i < HASHLEN; i++) {
      x = *(bp + i);
      if (x != 0) {
         for(j = 7; j > 0; j--) {
            x >>= 1;
            if(x == 0) {
               n += j;
               break;
            }
         }
      break;
      }
      n += 8;
      continue;
   }
   if(n >= d) return 0;
   return 1;
}
int v24(BTRAILER *bt, word32 difficulty, byte *haiku, word32 *hps, int mode)
{
   FILE *fp;

   SHA256_CTX ictx, mctx; /* Index & Mining Contexts */

   byte *workfield, *tfile, indexhash[HASHLEN], solution[HASHLEN], diff;

   uint64_t count, total, h, i, j, k, m, n, x, blocknum, tfsize, tfsizechk, index; /* 64-bit Memory Index Value */

   h = 0;

start_mine:
   if(!Running && mode == 0) goto out; /* SIGTERM Received */
  
   h += 1;

   diff = difficulty; /* down-convert passed-in 32-bit difficulty to 8-bit */

   count = total = i = j = k = m = n = x = tfsize = tfsizechk = index = 0;

/* Allocate WORKFIELD on the Heap */
   workfield = (byte*)malloc(WORKFIELD);
   if(workfield == NULL) {
      if(Trace) plog("Fatal: Unable to allocate memory for workfield.\n");
      goto out;
   }
   memset(workfield, 0, WORKFIELD);

/* In mode 0, add random haiku to the passed-in candidate block trailer */
/* If mode == 1, we're validating, so there's already a nonce there. */
   if(mode == 0) {
      memset(&bt->nonce[0], 0, HASHLEN);
      trigg_gen(&bt->nonce[0]);
      trigg_gen(&bt->nonce[16]);
   }

/* Open trailer file to load to memory. */
   fp = fopen("tfile.dat", "rb");
   if(fp == NULL) {
      if(Trace) plog("Fatal: Unable to open T-file.\n");
      goto out;
   }

   blocknum = get32(bt->bnum);

/* Get the first previous neogenesis block number */
   blocknum = ((blocknum / 256) * 256) - 256;

/* Determine Expected trailer file size */
   tfsize = blocknum * TRLSIZE;

/* Collect size of Tfile in bytes, perform sanity check */
   fseek(fp, 0, SEEK_END);
   tfsizechk = ftell(fp);
   fseek(fp, 0, SEEK_SET);

   if(tfsize > tfsizechk){ /* She needs something bigger. */
      if(Trace) plog("Fatal: T-File Size on disk is just too small.\n");
      goto out;
   }

   if(tfsizechk > WORKFIELD) { /* Won't happen for 200+ years */
      if(Trace) plog("Fatal: T-File Size > WORKFIELD.\n");
      goto out;
   }

/* Allocate T-file on the Heap */
   tfile = (byte*)malloc(tfsize);
   if(tfile == NULL) {
      if(Trace) plog("Fatal: Can't allocate space on the Heap for T-file.\n");
      goto out;
   }
   memset(tfile, 0, tfsize);

/* Copy T-file to memory */
   for(j = 0; j < tfsize/TRLSIZE ; j++) {
      count = fread(tfile + j*TRLSIZE, 1, TRLSIZE, fp);
      total += count;
      if(count != TRLSIZE) {
         if(Trace) plog("Fatal: Bad read on T-file, expected count: %d, got " \
                        "count: %lld, loop: %lld, total read was: %lld.\n",\
                        TRLSIZE, count, j, total);
         goto out;
      }
   }

/* Fill Work Field with as many full copies of the T-File as we can */
   total = 0;
   for(k = 0; total + tfsize < WORKFIELD; k++) {
      memcpy(workfield + (k*tfsize), tfile, tfsize);
      total += tfsize;
   }

/* Fill remaining empty Work Field with a partial T-file */
   memcpy(workfield + total, tfile, WORKFIELD - total);
   free(tfile); /* done with tfile */
   tfile = NULL;

   sha256_init(&ictx);
   sha256_update(&ictx, (byte *) bt, 124);
   memcpy(&mctx, &ictx, sizeof(ictx));

   sha256_final(&ictx, indexhash);

   for(j = 0; j < 8; j++) {
      index += *((word32 *) indexhash + j);
      if (index > (WORKFIELD - 32)) index %= (WORKFIELD - 32);
      sha256_update(&mctx, (byte *) workfield + index, HASHLEN);
   }
   sha256_final(&mctx, solution);

   if(mode == 1) { /* Just Validating, not Mining, check once and return */
      trigg_expand2(bt->nonce, &haiku[0]);
      if(Trace) plog("\nV:%s\n\n", haiku);

      if(workfield != NULL) free(workfield);
      if(tfile != NULL) free(tfile);

      if(fp != NULL) fclose(fp);
      workfield = tfile = NULL;
      fp = NULL;
      return v24_eval(solution, diff); /* Return 0 if valid, 1 if not valid */
   }

   if(v24_eval(solution, diff) == 0) { /* We're Mining & We Solved! */

      *hps = h;

      trigg_expand2(bt->nonce, &haiku[0]);
      if(Trace) plog("\nS:%s\n\n", haiku);

      if(workfield != NULL) free(workfield);
      if(tfile != NULL) free(tfile);

      if(fp != NULL) fclose(fp);
      workfield = tfile = NULL;
      fp = NULL;
      return 0;
   }

out:
   if(workfield != NULL) free(workfield);
   if(tfile != NULL) free(tfile);

   if(fp != NULL) fclose(fp);
   workfield = tfile = NULL;
   fp = NULL;

   if(!Running) return 1; /* SIGTERM RECEIVED */
   goto start_mine; /* Didn't Solve, Try Again */

} /* End v24() */
