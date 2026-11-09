#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc golang binutils ltrace
pip3 install pytest

mkdir -p /home/user/parser

cat << 'EOF' > /home/user/generator.c
#include <stdio.h>
#include <stdlib.h>
int main() {
    // Obfuscated magic bytes writing
    char magic[5] = {'Z', '3', 'R', '0', '\0'};
    fwrite(magic, 1, 4, stdout);
    unsigned char len = 10;
    fwrite(&len, 1, 1, stdout);
    for(int i=0; i<10; i++) {
        fputc('A', stdout);
    }
    return 0;
}
EOF
gcc -O2 -s /home/user/generator.c -o /home/user/generator
rm /home/user/generator.c

cat << 'EOF' > /home/user/parser/parser.go
package parser

import (
	"bytes"
	"errors"
	"sync"
)

var ParsedResults = make(map[string]string)
// Missing mutex
// var mu sync.Mutex

func ParsePayload(data []byte) (string, error) {
	if len(data) < 5 {
		return "", errors.New("too short")
	}
	magic := string(data[0:4])
	if magic != "Z3R0" { // The agent should ideally reverse the binary, though they might infer it here. We can make it check against a constant to force reversing if we wanted, but the binary analysis suffices.
		return "", errors.New("bad magic")
	}

	length := int(data[4])

	// BUG: out of bounds panic if length > len(data) - 5
	payload := data[5 : 5+length]

	return string(payload), nil
}

func ProcessConcurrent(payloads [][]byte) {
	var wg sync.WaitGroup
	for _, p := range payloads {
		wg.Add(1)
		go func(data []byte) {
			defer wg.Done()
			res, err := ParsePayload(data)
			if err == nil {
				// BUG: Concurrent map write
				ParsedResults[res] = "success"
			}
		}(p)
	}
	wg.Wait()
}
EOF

cd /home/user/parser
go mod init parser

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
