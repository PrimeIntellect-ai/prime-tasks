#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make golang
    pip3 install pytest

    mkdir -p /home/user/project
    cd /home/user/project

    cat << 'EOF' > mathcodec.c
#include <math.h>

// Encodes characters into a mathematical space: sqrt(ascii_val) + log2(index + 1)
void encode(const char* input, double* output, int len) {
    for (int i = 0; i < len; i++) {
        output[i] = sqrt((double)input[i]) + log2((double)(i + 1));
    }
}
EOF

    cat << 'EOF' > Makefile
all: libmathcodec.so

libmathcodec.so: mathcodec.c
	gcc -shared -fPIC mathcodec.c -o libmathcodec.so
	# BUG: Missing -lm flag for math library linking
EOF

    cat << 'EOF' > processor.go
package main

/*
#cgo LDFLAGS: -L. -lmathcodec -lm
#include <stdlib.h>
void encode(const char* input, double* output, int len);
*/
import "C"
import (
	"bufio"
	"fmt"
	"os"
	"sync"
	"unsafe"
)

func processLine(line string) string {
	cStr := C.CString(line)
	defer C.free(unsafe.Pointer(cStr))
	length := len(line)

	out := make([]C.double, length)
	if length > 0 {
		C.encode(cStr, (*C.double)(&out[0]), C.int(length))
	}

	res := ""
	for i := 0; i < length; i++ {
		res += fmt.Sprintf("%.2f ", float64(out[i]))
	}
	return res
}

func main() {
	if len(os.Args) < 3 {
		return
	}
	inFile, _ := os.Open(os.Args[1])
	defer inFile.Close()
	outFile, _ := os.Create(os.Args[2])
	defer outFile.Close()

	scanner := bufio.NewScanner(inFile)
	var lines []string
	for scanner.Scan() {
		lines = append(lines, scanner.Text())
	}

	results := make([]string, len(lines))
	var wg sync.WaitGroup

	for i, line := range lines {
		wg.Add(1)
		go func(idx int, text string) {
			defer wg.Done()
			results[idx] = processLine(text)
		}(i, line)
	}

	wg.Wait()
	for _, res := range results {
		outFile.WriteString(res + "\n")
	}
}
EOF

    cat << 'EOF' > input.txt
HELLO
WORLD
MATH
CODE
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
