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