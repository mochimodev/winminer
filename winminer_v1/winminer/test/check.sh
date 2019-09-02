#!/bin/sh
clang -c -x cl -cl-std=CL1.2 -Xclang -finclude-default-header ../algo/peach/cl_peach.cl -o tmp.o
clang -c -x cl -cl-std=CL1.2 -Xclang -finclude-default-header ../crypto/hash/opencl/cl_blake2b.cl -o tmp.o
clang -c -x cl -cl-std=CL1.2 -Xclang -finclude-default-header ../crypto/hash/opencl/cl_sha1.cl -o tmp.o
clang -c -x cl -cl-std=CL1.2 -Xclang -finclude-default-header ../crypto/hash/opencl/cl_sha256.cl -o tmp.o
clang -c -x cl -cl-std=CL1.2 -Xclang -finclude-default-header ../crypto/hash/opencl/cl_keccak.cl -o tmp.o
clang -c -x cl -cl-std=CL1.2 -Xclang -finclude-default-header ../crypto/hash/opencl/cl_md2.cl -o tmp.o
clang -c -x cl -cl-std=CL1.2 -Xclang -finclude-default-header ../crypto/hash/opencl/cl_md5.cl -o tmp.o
rm tmp.o
