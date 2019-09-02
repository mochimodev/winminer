typedef uchar uint8_t;
typedef int int32_t;
typedef uint uint32_t;
typedef long int64_t;
typedef ulong uint64_t;
typedef uchar BYTE;             // 8-bit byte
typedef uint  WORD;             // 32-bit word, change to "long" for 16-bit machines
typedef ulong LONG;
#define __forceinline__ inline
#define memcpy(dst,src,size); { for (int mi = 0; mi < size; mi++) { ((local uint8_t*)dst)[mi] = ((local uint8_t*)src)[mi]; } }
#define __CL_ENABLE_EXCEPTIONS
#pragma OPENCL EXTENSION cl_khr_int64_base_atomics : enable

/**
 * Performs data transformation on 32 bit chunks (4 bytes) of data
 * using deterministic floating point operations on IEEE 754
 * compliant machines and devices.
 * @param *data     - pointer to in data (at least 32 bytes)
 * @param len       - length of data
 * @param index     - the current tile
 * @param *op       - pointer to the operator value
 * @param transform - flag indicates to transform the input data */
void cuda_fp_operation(uint8_t *data, uint32_t len, uint32_t index,
                                  uint32_t *op, uint8_t transform, uint8_t debug)
{
   uint8_t *temp;
   uint32_t adjustedlen;
   int32_t i, j, operand;
   float floatv, floatv1;
   float *floatp;
   
   /* Adjust the length to a multiple of 4 */
   adjustedlen = (len >> 2) << 2;
   //adjustedlen = 32;

   /* Work on data 4 bytes at a time */
   for(i = 0; i < adjustedlen; i += 4)
   {
      /* Cast 4 byte piece to float pointer */
      if(transform) {
         floatp = (float *) &data[i];
      } else {
         floatv1 = *(float *) &data[i];
         floatp = &floatv1;
      }

      /* 4 byte separation order depends on initial byte:
       * #1) *op = data... determine floating point operation type
       * #2) operand = ... determine the value of the operand
       * #3) if(data[i ... determine the sign of the operand
       *                   ^must always be performed after #2) */
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

      /* Replace pre-operation NaN with index */
      if(isnan(*floatp)) *floatp = index;

      /* Perform predetermined floating point operation */
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
	 default:
	    break;
      }

      /* Replace post-operation NaN with index */
      if(isnan(*floatp)) *floatp = index;
      //printf("*floatp: %f\n", *floatp);

      /* Add result of floating point operation to op */
      temp = (uint8_t *) floatp;
      printf("temp: %x %x %x %x\n", temp[0], temp[1], temp[2], temp[3]);
      for(j = 0; j < 4; j++) {
         *op += temp[j];
      }
   } /* end for(*op = 0... */
}

__kernel void cuda_build_map(__global uint8_t *g_map, __global uint8_t *c_phash) {
	uint8_t data[256];
	uint32_t len = 256;
	for (int i = 0; i < len; i++) {
		data[i] = 1;
	}
	uint32_t index = 0;
	uint32_t op;
	op = 1;
	uint32_t transform = 0;
	cuda_fp_operation(data, len, index, &op, transform, 0);
}
