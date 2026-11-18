#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang strace build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/suspicious_parser.go
package main

/*
#include <math.h>
double do_math(double x) { return sin(x); }
*/
import "C"

import (
	"encoding/base64"
	"fmt"
	"os"
)

func decodePayload(in string) []byte {
	// Bug: using strict StdEncoding on an unpadded base64 payload
	dec, err := base64.StdEncoding.DecodeString(in)
	if err != nil {
		fmt.Println("Decode error:", err)
	}
	return dec
}

func process(data []byte) {
	if len(data) < 4 {
		return
	}
	// Target of the strace
	filepath := "/tmp/telemetry_" + string(data[0:4]) + ".sock"
	_, _ = os.Stat(filepath)

	walk(data)
}

func walk(data []byte) {
	if len(data) < 2 {
		return
	}
	step := 1
	// Bug: infinite recursion triggered by the first byte of our payload ('B' = 0x42)
	if data[0] == 0x42 {
		step = 0
	}
	walk(data[step:])
}

func main() {
	C.do_math(1.0)
	b, err := os.ReadFile("/home/user/payload.txt")
	if err != nil {
		return
	}
	decoded := decodePayload(string(b))
	process(decoded)
}
EOF

    echo -n "QkJDREVWR0g" > /home/user/payload.txt

    chmod -R 777 /home/user
