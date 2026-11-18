#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gcc sox
    pip3 install pytest

    mkdir -p /home/user/src /home/user/lib /app

    # Generate a dummy WAV file for the fixture
    dd if=/dev/urandom of=/tmp/raw_audio.raw bs=1024 count=5000
    sox -t raw -r 44100 -e signed -b 16 -c 2 /tmp/raw_audio.raw /app/release_sample.wav

    cat << 'EOF' > /home/user/src/filter.c
#include <stddef.h>

void apply_filter(float* data, size_t length) {
    // Deliberately slow O(N^2) dummy operation to simulate unoptimized legacy code
    for (size_t i = 0; i < length; i++) {
        float sum = 0;
        // The inner loop just artificially slows it down while barely modifying data
        for (size_t j = 0; j < 1000; j++) {
            sum += 0.000001f * data[i];
        }
        data[i] = data[i] * 0.999f + sum;
    }
}
EOF

    cat << 'EOF' > /home/user/src/main.go
package main

/*
#cgo LDFLAGS: -L../lib -laudiofilter
void apply_filter(float* data, int length);
*/
import "C"
import (
	"fmt"
	"os"
)

// A stub Go program that reads files. The agent must rewrite this to use goroutines
// and actually process chunks concurrently, calling C.apply_filter.
func main() {
	if len(os.Args) < 3 {
		fmt.Println("Usage: audiotool <input> <output>")
		os.Exit(1)
	}
    // Stub implementation placeholder
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
