#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/migrator
    cd /home/user/migrator

    cat << 'EOF' > moving_average.h
#ifndef MOVING_AVERAGE_H
#define MOVING_AVERAGE_H

float* moving_average(float* data, int n, int window);

#endif
EOF

    cat << 'EOF' > moving_average.c
#include "moving_average.h"
#include <stdlib.h>

// BUG: returning pointer to local stack variable
float* moving_average(float* data, int n, int window) {
    int out_len = n - window + 1;
    if (out_len <= 0) return NULL;

    float result[1000]; // Local stack array
    for (int i = 0; i < out_len; i++) {
        float sum = 0;
        for (int j = 0; j < window; j++) {
            sum += data[i+j];
        }
        result[i] = sum / window;
    }
    return result;
}
EOF

    cat << 'EOF' > main.go
package main

/*
#cgo CFLAGS: -g -Wall
#include "moving_average.h"
#include <stdlib.h>
*/
import "C"
import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"unsafe"
)

func computeMA(data []float32, window int) []float32 {
	if len(data) < window || window <= 0 {
		return nil
	}

	cData := (*C.float)(C.malloc(C.size_t(len(data)) * C.size_t(unsafe.Sizeof(C.float(0)))))
	defer C.free(unsafe.Pointer(cData))

	// Copy data to C array
	cDataSlice := (*[1 << 30]C.float)(unsafe.Pointer(cData))[:len(data):len(data)]
	for i, v := range data {
		cDataSlice[i] = C.float(v)
	}

	outLen := len(data) - window + 1
	cResult := C.moving_average(cData, C.int(len(data)), C.int(window))
	if cResult == nil {
		return nil
	}
	defer C.free(unsafe.Pointer(cResult))

	result := make([]float32, outLen)
	cResultSlice := (*[1 << 30]C.float)(unsafe.Pointer(cResult))[:outLen:outLen]
	for i := 0; i < outLen; i++ {
		result[i] = float32(cResultSlice[i])
	}

	return result
}

func main() {
	if len(os.Args) < 3 {
		fmt.Println("Usage: ma_cli <comma-separated-floats> <window>")
		os.Exit(1)
	}

	parts := strings.Split(os.Args[1], ",")
	var data []float32
	for _, p := range parts {
		val, err := strconv.ParseFloat(p, 32)
		if err == nil {
			data = append(data, float32(val))
		}
	}

	window, _ := strconv.Atoi(os.Args[2])
	res := computeMA(data, window)

	for i, v := range res {
		if i > 0 {
			fmt.Print(",")
		}
		fmt.Printf("%.1f", v)
	}
	fmt.Println()
}
EOF

    cat << 'EOF' > integration.py
import subprocess
import sys

def run_test():
    print "Starting integration test..."
    try:
        p = subprocess.Popen(["./ma_cli", "10.0,20.0,30.0,40.0", "2"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        out, err = p.communicate()
        out_str = out.decode('utf-8').strip()
        if out_str == "15.0,25.0,35.0":
            print "Integration test PASSED"
            sys.exit(0)
        else:
            print "Integration test FAILED. Got:", out_str
            sys.exit(1)
    except Exception as e:
        print "Error:", e
        sys.exit(1)

if __name__ == "__main__":
    run_test()
EOF

    go mod init migrator

    chmod -R 777 /home/user
