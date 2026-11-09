#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go g++ make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/pr_review

    cat << 'EOF' > /home/user/pr_review/signatures.txt
eval base64_decode
union select
script alert
EOF

    cat << 'EOF' > /home/user/pr_review/payloads.csv
1,hello world this is safe
2,an attack with union and select statement
3,eval base64_decode something bad
4,normal traffic with eval but no decode
5,a script alert xss attempt
6,union all but no select here
EOF

    cat << 'EOF' > /home/user/pr_review/main.go
package main

/*
#cgo CFLAGS: -I.
#cgo LDFLAGS: -L. -ldetector
#include "detector.h"
#include <stdlib.h>
*/
import "C"
import (
	"bufio"
	"fmt"
	"os"
	"strings"
	"sync"
	"unsafe"
)

func main() {
	sigBytes, _ := os.ReadFile("signatures.txt")
	sigCStr := C.CString(string(sigBytes))
	defer C.free(unsafe.Pointer(sigCStr))

	file, _ := os.Open("payloads.csv")
	defer file.Close()

	scanner := bufio.NewScanner(file)
	var wg sync.WaitGroup
	ch := make(chan string)

	// fan-out workers
	for i := 0; i < 4; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for line := range ch {
				parts := strings.SplitN(line, ",", 2)
				if len(parts) != 2 {
					continue
				}
				id := parts[0]
				payload := parts[1]

				payloadC := C.CString(payload)
				isThreat := C.detect_threat(payloadC, sigCStr)
				C.free(unsafe.Pointer(payloadC))

				if isThreat == 1 {
					fmt.Println(id)
				}
			}
		}()
	}

	for scanner.Scan() {
		ch <- scanner.Text()
	}
	close(ch)
	wg.Wait()
}
EOF

    cat << 'EOF' > /home/user/pr_review/detector.h
#ifndef DETECTOR_H
#define DETECTOR_H

#ifdef __cplusplus
extern "C" {
#endif

int detect_threat(const char* payload, const char* signatures);

#ifdef __cplusplus
}
#endif

#endif
EOF

    cat << 'EOF' > /home/user/pr_review/detector.cpp
#include "detector.h"
#include <string>
#include <vector>
#include <sstream>
#include <algorithm>

// Broken implementation
int detect_threat(const char* payload, const char* signatures) {
    std::string p(payload);
    std::string s(signatures);

    // bug: doesn't properly split signatures by newline
    // bug: sorting and subset checking is wrong
    if (p.find("union") != std::string::npos) return 1;
    return 0;
}
EOF

    chmod -R 777 /home/user
