#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make golang
pip3 install pytest

mkdir -p /home/user/ci-tools/c-encoder
mkdir -p /home/user/ci-tools/go-verifier

cat << 'EOF' > /home/user/ci-tools/c-encoder/encoder.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    char buffer[1024];
    int len = snprintf(buffer, sizeof(buffer), "%zu:%s", strlen(argv[1]), argv[1]);
    for (int i = 0; i < len; i++) {
        printf("%02x", (unsigned char)buffer[i]);
    }
    printf("\n");
    return 0;
}
EOF

cat << 'EOF' > /home/user/ci-tools/c-encoder/Makefile
encoder: encoder.c
    gcc -O2 encoder.c -o encoder
EOF

cat << 'EOF' > /home/user/ci-tools/go-verifier/go.mod
module verifier

go 1.20
EOF

cat << 'EOF' > /home/user/ci-tools/go-verifier/verifier_test.go
package verifier

import (
	"bytes"
	"fmt"
	"os/exec"
	"strings"
	"testing"
	"math/rand"
)

func randomString(n int) string {
	var letters = []rune("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
	s := make([]rune, n)
	for i := range s {
		s[i] = letters[rand.Intn(len(letters))]
	}
	return string(s)
}

func TestEncoderProperty(t *testing.T) {
	// TODO: Spawn 50 goroutines to run the test concurrently.
	// Generate a random string using randomString(10 + rand.Intn(20))
	// Pass it to exec.Command("../c-encoder/encoder", randStr)
	// TODO: Hex decode the stdout.
	// Verify it matches fmt.Sprintf("%d:%s", len(randStr), randStr)
	// Use channels to collect results.

	t.Fatal("Not implemented")
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
