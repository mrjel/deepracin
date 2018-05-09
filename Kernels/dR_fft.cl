/**
* \brief Transforms grayscale image to frequency spectrum
* \param[in] Input, real and imaginary parts
* \param[out] Output, real and imaginary parts
* \author
*/

/* The implementation is inspired by http://www.bealto.com/gpu-fft_opencl-1.html */

/* Return real or imaginary component of complex number */
#define SQRT2 1.41421356237309504880f

inline float real(float2 a){
     return a.x;
}
inline float imag(float2 a){
     return a.y;
}

/* Complex multiplication */
#define MUL(a, b, tmp) { tmp = a; a.x = tmp.x*b.x - tmp.y*b.y; a.y = tmp.x*b.y + tmp.y*b.x; }

/* Butterfly operation */
#define DFT2( a, b, tmp) { tmp = a - b; a += b; b = tmp; }

/* Return e^(i*alpha) = cos(alpha) + I*sin(alpha) */
float2 exp_alpha(float alpha)
{
  float cs,sn;
  sn = sincos(alpha,&cs);
  return (float2)(cs,sn);
}

float sampleZeroPaddedFloatFFT(
  __global float * in,
  int imag_offset,
  int width_offset,
  int x,
  int y,
  int width,
  int real_width,
  int real_height
)
{
  if(x<0 || (x + width_offset)>=(real_width)|| y<0 || y>=real_height)
  {
    return 0.0f;
  }
  else
  {
    return in[imag_offset + width_offset + (y*width + x)];
  }
}

/******************** 2D grayscale fft *********************/
__kernel void fft(
  __global float * in,
  __global float * out,
  int p,
  int real_width,
  int real_height,
  int r_c
)
{
  int gx = get_global_id(0);
  int gy = get_global_id(1);
  int width = (int) get_global_size(0)*2;
  int height = (int) get_global_size(1);
  int offset = gy*width;
  int gid = width*gy + gx;
  int imag_offset = width*height;

  int k = (gx) & (p-1);

  float2 u0;
  float2 u1;

  if (p == 1 && r_c == 1) // first fft iteration, input is real
  {
    //sampleZeroPaddedFloatFFT(in,imag_offset,width_offset,gx,gy,width,real_width, real_height);
    //TODO: check if really needed for upper element of butterfly
    u0.x = sampleZeroPaddedFloatFFT(in,0,0,gx,gy,width,real_width,real_height);
    u0.y = 0;

    u1.x = sampleZeroPaddedFloatFFT(in,0,(width/2),gx,gy,width,real_width,real_height);
    u1.y = 0;
  }
  else // get real and imaginary part
  {
    u0.x = sampleZeroPaddedFloatFFT(in,0,0,gx,gy,width,real_width,real_height); //real part
    u0.y = sampleZeroPaddedFloatFFT(in,imag_offset,0,gx,gy,width,real_width, real_height); //imag part

    u1.x = sampleZeroPaddedFloatFFT(in,0,(width/2),gx,gy,width,real_width, real_height);
    u1.y = sampleZeroPaddedFloatFFT(in,imag_offset,(width/2),gx,gy,width,real_width, real_height);
  }

  float2 twiddle;
  float2 tmp;

  twiddle = exp_alpha( (float)(k)*(-1)*M_PI_F / (float)(p) );

  MUL(u1,twiddle,tmp);

  DFT2(u0,u1,tmp);

  int j = ((gx) << 1) - k;
  j += offset;


  out[j] = real(u0);
  if(!(gx<0 || (gx + p)>=(real_width)|| gy<0 || gy>=real_height))
    out[j + p] = real(u1);

  out[j + imag_offset] = imag(u0);
  if(!(gx<0 || (gx + p)>=(real_width)|| gy<0 || gy>=real_height))
    out[j + p + imag_offset] = imag(u1);
}

// TODO: could do one kernel for forward and inv fft
__kernel void fft_inv(
  __global float * in,
  __global float * out,
  int p
)
{
  int gx = get_global_id(0);
  int gy = get_global_id(1);
  int width = (int) get_global_size(0)*2;
  int height = (int) get_global_size(1);
  int offset = gy*width;
  int gid = width*gy + gx;
  int imag_offset = width*height;

  int k = (gx) & (p-1);

  float2 u0;
  float2 u1;

  u0.x = in[gid]; //real part
  u0.y = in[gid + imag_offset]; //imag part

  u1.x = in[gid + (width/2)];
  u1.y = in[gid + (width/2) + imag_offset];

  float2 twiddle;
  float2 tmp;

  twiddle = exp_alpha( (float)(k)*M_PI_F / (float)(p) );

  MUL(u1,twiddle,tmp);

  DFT2(u0,u1,tmp);

  int j = ((gx) << 1) - k;
  j += offset;

  out[j] = real(u0);
  out[j + p] = real(u1);

  out[j + imag_offset] = imag(u0);
  out[j + p + imag_offset] = imag(u1);
}

// TODO: (1) implement these helper kernels as string in dR_nodes_fft.c ? (2) rename kernels to fft_x or x_fft, e.g. fft_copy or copy_fft ?
 __kernel void copy(
  __global float * in,
  __global float * out,
  int real_width,
  int real_height
)
{
  int gx = get_global_id(0);
  int gy = get_global_id(1);
  int gz = get_global_id(2);
  int width = (int) get_global_size(0);
  int height = (int) get_global_size(1);
  int gid = width*height*gz + width*gy + gx;

  if(!(gx<0 || (gx)>=(real_width)|| gy<0 || gy>=real_height))
    out[gid] = in[gid];
}

// TODO: use more optimized version
__kernel void transpose(
  __global float * in,
  __global float * out,
  int real_width,
  int real_height
)
{
  int gx = get_global_id(0);
  int gy = get_global_id(1);
  int gz = get_global_id(2);
  int width = (int) get_global_size(0);
  int height = (int) get_global_size(1);

  if( !(gx<0 || gx>=real_width || gy<0 || gy>=real_height) )
  {
    int gid = width*height*gz + width*gy + gx;
    int t_gid = width*height*gz + width*gx + gy;
    out[t_gid] = in[gid];
  }
}

__kernel void normalizeFFT(
  __global float *out,
  int real_width,
  int real_height
)
{
  int gx = get_global_id(0);
  int gy = get_global_id(1);
  int gz = get_global_id(2);
  int width = (int) get_global_size(0);
  int height = (int) get_global_size(1);
  int gid = width*height*gz + width*gy + gx;

  if(!(gx<0 || (gx)>=(real_width)|| gy<0 || gy>=real_height))
    out[gid] /= (width*height);
}

// for fftshift: https://www.researchgate.net/publication/271457994_High_performance_multi-dimensional_2D3D_FFT-Shift_implementation_on_Graphics_Processing_Units_GPUs
// https://www.researchgate.net/publication/278847958_CufftShift_High_performance_CUDA-accelerated_FFT-shift_library
// TODO: (1) could be done in-place. out-of-place has less temporal values (2) if only quadratic images, use only width

/*
1 2  becomes  4 3
3 4           2 1
*/
__kernel void shiftFFT(
  __global float *in,
  __global float *out
  )
  {
    int width = (int) get_global_size(0);
    int height = (int) get_global_size(1);
    int gx = get_global_id(0);
    int gy = get_global_id(1);
    int gid = gy*width + gx;
    int imag_offset = width*height;
    int eq1 = ((width*height) + width)/2;
    int eq2 = ((width*height) - height)/2;

    if (gx < width/2)
    {
      if (gy < height/2)
      {
        // swap first quadrant with fourth
        out[gid] = in[gid+eq1];
        out[gid+eq1] = in[gid];

        out[gid + imag_offset] = in[gid + eq1 + imag_offset];
        out[gid + eq1 + imag_offset] = in[gid + imag_offset];
      }
    }
    else
    {
      if (gy < height/2)
      {
        // swap second quadrant with third
        out[gid] = in[gid + eq2];
        out[gid+eq2] = in[gid];

        out[gid + imag_offset] = in[gid + eq2 + imag_offset];
        out[gid + eq2 + imag_offset] = in[gid + imag_offset];
      }
    }
  }

  // magnitude of fft
  __kernel void absFFT(
    __global float *in,
    __global float *out
    )
    {
      int width = (int) get_global_size(0);
      int height = (int) get_global_size(1);
      int gx = get_global_id(0);
      int gy = get_global_id(1);
      int gid = gy*width + gx;
      int imag_offset = width*height;

      float real = in[gid];
      float imag = in[gid + imag_offset];
      real *= real;
      imag *= imag;
      out[gid] = sqrt(real + imag);
    }


  __kernel void haarwt(
    __global float *in,
    __global float *out,
    int img_width
    )
    {
      int width = (int) get_global_size(0);
      int gx = get_global_id(0);
      int gy = get_global_id(1);

      out[img_width*gy + gx] = in[img_width*gy + 2*gx] + in[img_width*gy + 2*gx + 1];
      out[img_width*gy + gx] /= SQRT2;
      out[img_width*gy + width + gx] = in[img_width*gy + 2*gx] - in[img_width*gy + 2*gx + 1];
      out[img_width*gy + width + gx] /= SQRT2;
    }

    __kernel void hwtcopy(
     __global float * in,
     __global float * out
   )
   {
     int gx = get_global_id(0);
     int gy = get_global_id(1);
     int width = (int) get_global_size(0);
     int gid = width*gy + gx;

     out[gid] = in[gid];
   }

   __kernel void hwttranspose(
     __global float * in,
     __global float * out
   )
   {
     int gx = get_global_id(0);
     int gy = get_global_id(1);
     int width = (int) get_global_size(0);
     int gid =  width*gy + gx;
     int t_gid = width*gx + gy;

     out[t_gid] = in[gid];
   }

   // calculate all energy summands in-place
   __kernel void wenergy2All(
     __global float * in
   )
   {
     int gx = get_global_id(0);
     int gy = get_global_id(1);
     int width = (int) get_global_size(0);
     int height = (int) get_global_size(1);
     int gid =  width*gy + gx;

     in[gid] = in[gid]*in[gid];
    }

    /*
   // calculate energy of a subset
   // TODO: use partial sum reduction
   __kernel void wenergy2Subset(
     __global float * in,
     __global float * feat,
     __local float * lsum,
     int key,// where to store sum element
     int gidOfLastValidElement,
   )
   {
     // global positions
     int gx = get_global_id(0);
     int gy = get_global_id(1);
     int width = (int) get_global_size(0);
     int height = (int) get_global_size(1);
     int gid = width*gy + gx;

     // local position, w*gy + gx for local ids
     int lid = (int)get_local_id(1)*(int)get_local_size(0) + (int)get_local_id(0);
     // total nr of active threads
     int nActiveThreads = (int)get_local_size(0) * (int)get_local_size(1);

     int halfPoint = 0;

     // initialize with neutral element
     lsum[lid] = 0.0f;
     gidOfLastValidElement = gidOfLastValidElement+((int)get_global_id(1)*(int) get_global_size(0));

     //read to local memory
     lsum[lid] = in[gid];

     //wait for all threads to read one value of the (e.g.) 256 values
     barrier(CLK_LOCAL_MEM_FENCE);

     while(nActiveThreads > 1)
     {
         halfPoint = (nActiveThreads >> 1);	// divide by two
         // only the first half of the threads will be active.
         // in this round the first half of threads reads what the last half of threads calculated in the previous round
         // it compares the lmax[lid + halfPoint] value with the value lmax[lid]
         // continues until only one thread is left (all other threads are still running but inactive)
         if (lid < halfPoint)
         {
             // Get the shared value stored by another thread (of the last half) then compare the two values and keep the lesser one
             lsum[lid] += lsum[lid + halfPoint];

         }

         barrier(CLK_LOCAL_MEM_FENCE);

         nActiveThreads = halfPoint;	//only first half stays active
     } //while(nActiveThreads > 1)


     if (lid == 0)
     {
         feat[0] = lsum[0];
     }

     //feat[0] = in[gid] + feat[0];
   }
   */

   // inspired by https://github.com/maoshouse/OpenCL-reduction-sum
   // and https://dournac.org/info/gpu_sum_reduction
   // http://developer.download.nvidia.com/compute/cuda/1.1-Beta/x86_website/projects/reduction/doc/reduction.pdf

   #if 1
  __kernel void wenergy2Sum(
    __global float *input,
    __global float *output,
    __local float *reductionSums
  )
  {
    	const int globalID = (int)get_global_id(1) * (int)get_global_size(0) + (int)get_global_id(0);

    	const int localID = (int)get_local_id(1)*(int)get_local_size(0) + (int)get_local_id(0);

    	const int localSize = get_local_size(0)*get_local_size(1);
      //output[0] = 0.0f;
      //reductionSums[localID] = 0.0f;
    	reductionSums[localID] = input[globalID];

    	for(int offset = localSize / 2; offset > 0; offset /= 2)
      {
      		if(localID < offset)
          {
      			  reductionSums[localID] += reductionSums[localID + offset];
      		}
      		barrier(CLK_LOCAL_MEM_FENCE);	// wait for all other work-items to finish previous iteration.
    	}

      // TODO: for more speedup, do this last summation on CPU
    	if(localID == 0)
      {
    		   output[0] += reductionSums[0];
    	}
  }
  #endif


   // TODO: to sum all values, do parallel sum reduction
   // https://dournac.org/info/gpu_sum_reduction

   // Output energy on 3 levels.
   /*
   Image segments in Wavelet decimation
   1 2
   3 4
   */
   __kernel void wenergy2_3(
     __global float * in,
     __global float * feat
   )
   {
     int gx = get_global_id(0);
     int gy = get_global_id(1);
     int width = (int) get_global_size(0);
     int height = (int) get_global_size(1);
     int gid =  width*gy + gx;

     // calculate total energy


     // Level 1 Energy
     if (gx < width/2)
     {
       // left part of image
       if (gy < height/2)
       {
         // left top: 1. quadrant
         //Call again for w/2, h/2
         #if 0 // LVL 2
         // Level 2 energy
         if (gx < width/4)
         {
           // left part of image
           if (gy < height/4)
           {
             // left top: 1. quadrant lvl 2
             // Call again
             #if 1 // LVL 3
             // Level 3 energy
             if (gx < width/8)
             {
               // left part of image
               if (gy < height/8)
               {
                 // left top: 1. quadrant lvl 3
                 // No more recursions

               }
               else
               {
                 // left bottom: 3. quadrant lvl 3
               }
             }
             else
             {
               // right part of image
               if (gy < height/8)
               {
                 // right top: 2. quadrant lvl 3
               }
               else
               {
                 // right bottom: 4. quadrant lvl 3
               }
               // End of Level 3 decimation
               #endif
           }
           else
           {
             // left bottom: 3. quadrant
           }
         }
         else
         {
           // right part of image
           if (gy < height/4)
           {
             // right top: 2. quadrant lvl 2
           }
           else
           {
             // right bottom: 4. quadrant lvl 2
           }
           // End of level 2 Decimation
           #endif
       }
       else
       {
         // left bottom: 3. quadrant

       }
     }
     else
     {
       // right part of image
       if (gy < height/2)
       {
         // right top: 2. quadrant
       }
       else
       {
         // right bottom: 4. quadrant
       }
     }
     // End of level 1 decimation
   }
