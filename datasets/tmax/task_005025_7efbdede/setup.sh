#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest numpy matplotlib

    # Create directories
    mkdir -p /app/libspecfact-1.2.0
    mkdir -p /app/oracle

    # Create the C library source
    cat << 'EOF' > /app/libspecfact-1.2.0/specfact.c
#include <stdlib.h>
#include <math.h>

void factorize(double* matrix, int rows, int cols, int k, double* w_out, double* h_out) {
    for(int i=0; i<rows*k; i++) w_out[i] = 0.1 + (i % 10)*0.01;
    for(int i=0; i<k*cols; i++) h_out[i] = 0.1 + (i % 10)*0.01;

    for(int iter=0; iter<5; iter++) {
        for(int c=0; c<cols; c++) {
            for(int j=0; j<k; j++) {
                double num = 0, den = 0;
                for(int r=0; r<rows; r++) {
                    double w_rj = w_out[r*k + j];
                    num += w_rj * matrix[r*cols + c];
                    double wh_rc = 0;
                    for(int l=0; l<k; l++) wh_rc += w_out[r*k + l] * h_out[l*cols + c];
                    den += w_rj * wh_rc;
                }
                h_out[j*cols + c] *= (num / (den + 1e-9));
            }
        }
        for(int r=0; r<rows; r++) {
            for(int j=0; j<k; j++) {
                double num = 0, den = 0;
                for(int c=0; c<cols; c++) {
                    double h_jc = h_out[j*cols + c];
                    num += matrix[r*cols + c] * h_jc;
                    double wh_rc = 0;
                    for(int l=0; l<k; l++) wh_rc += w_out[r*k + l] * h_out[l*cols + c];
                    den += wh_rc * h_jc;
                }
                w_out[r*k + j] *= (num / (den + 1e-9));
            }
        }
    }
}
EOF

    # Create the broken Makefile
    cat << 'EOF' > /app/libspecfact-1.2.0/Makefile
CC=gcc
CFLAGS=-O2

all: libspecfact.so

specfact.o: specfact.c
	$(CC) $(CFLAGS) -c specfact.c -o specfact.o

libspecfact.so: specfact.o
	$(CC) -shared -o libspecfact.so specfact.o

clean:
	rm -f *.o *.so
EOF

    # Create the oracle pipeline
    cat << 'EOF' > /app/oracle/reference_pipeline
#!/usr/bin/env python3
import sys
import numpy as np
import ctypes
import os

def main():
    if len(sys.argv) != 3:
        sys.exit(1)
    infile = sys.argv[1]
    outfile = sys.argv[2]

    data = np.fromfile(infile, dtype=np.float64)
    data = data.reshape((256, 256))

    fft_data = np.fft.fft2(data)
    mag_spec = np.abs(fft_data)

    mag_spec += 1e-6

    lib_path = "/app/libspecfact-1.2.0/libspecfact.so"
    if not os.path.exists(lib_path):
        sys.exit(1)

    lib = ctypes.cdll.LoadLibrary(lib_path)

    rows, cols = 256, 256
    k = 4

    w_out = np.zeros((rows, k), dtype=np.float64)
    h_out = np.zeros((k, cols), dtype=np.float64)

    matrix_ptr = mag_spec.ctypes.data_as(ctypes.POINTER(ctypes.c_double))
    w_ptr = w_out.ctypes.data_as(ctypes.POINTER(ctypes.c_double))
    h_ptr = h_out.ctypes.data_as(ctypes.POINTER(ctypes.c_double))

    lib.factorize(matrix_ptr, rows, cols, k, w_ptr, h_ptr)

    w_scaled = np.clip(w_out * 255.0, 0, 255).astype(np.uint8)
    w_scaled.tofile(outfile)

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/oracle/reference_pipeline

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
