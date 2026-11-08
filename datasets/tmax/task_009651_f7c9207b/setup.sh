#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang g++ gcc
    pip3 install pytest

    mkdir -p /home/user/api-gateway
    cd /home/user/api-gateway

    cat << 'EOF' > sanitizer.cpp
#include <string.h>
#include <stdlib.h>

extern "C" {
    char* strip_tags(const char* input) {
        int len = strlen(input);
        // BUG: Allocating exactly `len` bytes, but we need `len + 1` for the null terminator.
        // In concurrent scenarios, writing the null terminator out of bounds corrupts the heap.
        char* out = (char*)malloc(len); 

        int j = 0;
        int in_tag = 0;
        for(int i = 0; i < len; i++) {
            if (input[i] == '<') in_tag = 1;
            else if (input[i] == '>') in_tag = 0;
            else if (!in_tag) {
                out[j++] = input[i];
            }
        }
        out[j] = '\0'; // OUT OF BOUNDS WRITE IF NO TAGS ARE STRIPPED
        return out;
    }

    void free_string(char* str) {
        free(str);
    }
}
EOF

    cat << 'EOF' > sanitizer_test.go
package main

/*
#cgo CXXFLAGS: -std=c++11
#include <stdlib.h>

char* strip_tags(const char* input);
void free_string(char* str);
*/
import "C"
import (
	"sync"
	"testing"
	"unsafe"
)

func sanitize(input string) string {
	cStr := C.CString(input)
	defer C.free(unsafe.Pointer(cStr))

	cOut := C.strip_tags(cStr)
	defer C.free_string(cOut)

	return C.GoString(cOut)
}

func TestConcurrentSanitization(t *testing.T) {
	var wg sync.WaitGroup
	inputs := []string{
		"Hello World",
		"<b>Hello</b> <i>World</i>",
		"<script>alert(1)</script>",
		"No tags here at all!",
		"An unfinished <tag",
	}

	// Concurrent property-based fuzzing simulation
	for i := 0; i < 1000; i++ {
		wg.Add(1)
		go func(iter int) {
			defer wg.Done()
			in := inputs[iter%len(inputs)]
			_ = sanitize(in)
		}(i)
	}
	wg.Wait()
}

func BenchmarkSanitize(b *testing.B) {
	for i := 0; i < b.N; i++ {
		sanitize("<b>Testing</b> benchmark <script>alert('test')</script>")
	}
}
EOF

    go mod init api-gateway

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
