#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang build-essential wget dos2unix
    pip3 install pytest

    # Create vendored kissfft directory
    mkdir -p /app/kissfft-1.3.1

    cat << 'EOF' > /app/kissfft-1.3.1/kiss_fft.h
#ifndef KISS_FFT_H
#define KISS_FFT_H
#include <stddef.h>

typedef struct {
    float r;
    float i;
} kiss_fft_cpx;

typedef struct kiss_fft_state* kiss_fft_cfg;

kiss_fft_cfg kiss_fft_alloc(int nfft, int inverse_fft, void * mem, size_t * lenmem);
void kiss_fft(kiss_fft_cfg cfg, const kiss_fft_cpx *fin, kiss_fft_cpx *fout);

#endif
EOF

    cat << 'EOF' > /app/kissfft-1.3.1/kiss_fft.c
#include "kiss_fft.h"
#include <stdlib.h>

struct kiss_fft_state {
    int nfft;
    int inverse;
};

kiss_fft_cfg kiss_fft_alloc(int nfft, int inverse_fft, void * mem, size_t * lenmem) {
    kiss_fft_cfg st = (kiss_fft_cfg)malloc(sizeof(struct kiss_fft_state));
    st->nfft = nfft;
    st->inverse = inverse_fft;
    return st;
}

void kiss_fft(kiss_fft_cfg cfg, const kiss_fft_cpx *fin, kiss_fft_cpx *fout) {
    for (int i=0; i<cfg->nfft; i++) {
        fout[i].r = fin[i].r;
        fout[i].i = fin[i].i;
    }
}
EOF

    cat << 'EOF' > /app/kissfft-1.3.1/Makefile
all:
	gcc -c kiss_fft.c -o kiss_fft.o
	gcc -shared -o libkissfft.so kiss_fft.o
EOF

    # Create workspace and Go app
    mkdir -p /home/user/workspace/fftapp/pkg/processor
    mkdir -p /home/user/workspace/fftapp/pkg/utils
    mkdir -p /home/user/workspace/fftapp/pkg/cgofft
    mkdir -p /home/user/workspace/patches

    cat << 'EOF' > /home/user/workspace/fftapp/go.mod
module fftapp

go 1.18
EOF

    cat << 'EOF' > /home/user/workspace/fftapp/main.go
package main

import (
	"fmt"
	"fftapp/pkg/processor"
)

func main() {
	fmt.Println("Starting FFT app...")
	processor.Process()
}
EOF

    cat << 'EOF' > /home/user/workspace/fftapp/pkg/processor/processor.go
package processor

import (
	"fmt"
	"fftapp/pkg/utils"
)

func Process() {
	fmt.Println("Processing...")
	utils.Helper()
}
EOF

    cat << 'EOF' > /home/user/workspace/fftapp/pkg/utils/utils.go
package utils

import (
	"fmt"
	"fftapp/pkg/processor"
)

func Helper() {
	fmt.Println("Helper...")
	// intentional circular dependency for setup
	_ = processor.Process
}
EOF

    cat << 'EOF' > /home/user/workspace/fftapp/pkg/cgofft/wrapper.go
package cgofft

// #cgo CFLAGS: -I/app/kissfft-1.3.1
// #cgo LDFLAGS: -L/home/user/workspace/lib -lkissfft
// #include "kiss_fft.h"
import "C"

func DoFFT() {
    // To be implemented
}
EOF

    # Create the patch file with CRLF line endings
    cat << 'EOF' > /home/user/workspace/patches/kiss_opt.patch
--- kiss_fft.c
+++ kiss_fft.c
@@ -14,6 +14,7 @@

 void kiss_fft(kiss_fft_cfg cfg, const kiss_fft_cpx *fin, kiss_fft_cpx *fout) {
     for (int i=0; i<cfg->nfft; i++) {
+        // optimized
         fout[i].r = fin[i].r;
         fout[i].i = fin[i].i;
     }
EOF
    unix2dos /home/user/workspace/patches/kiss_opt.patch

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
