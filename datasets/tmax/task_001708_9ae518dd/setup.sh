#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gcc nginx redis-server bc curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/cache-node

    cat << 'EOF' > /home/user/cache-node/hash_go.go
package cache

func HashGo(data []byte) uint32 {
    var hash uint32 = 5381
    for _, b := range data {
        hash = ((hash << 5) + hash) + uint32(b) // hash * 33 + c
    }
    return hash
}
EOF

    cat << 'EOF' > /home/user/cache-node/hash_test.go
package cache
import (
	"math/rand"
	"testing"
)
var testData []byte
func init() {
	testData = make([]byte, 10*1024*1024)
	rand.Read(testData)
}
func BenchmarkHashGo(b *testing.B) {
	for i := 0; i < b.N; i++ {
		HashGo(testData)
	}
}
func BenchmarkHashCGO(b *testing.B) {
	for i := 0; i < b.N; i++ {
		HashCGO(testData)
	}
}
EOF

    cat << 'EOF' > /home/user/cache-node/hash.c
#include <stdint.h>
#include <stddef.h>

uint32_t fast_hash_c(const uint8_t* data, size_t len) {
    // Agent must implement djb2 hash here with optimizations
    return 0;
}
EOF

    cd /home/user/cache-node
    go mod init cache-node
    go get github.com/go-redis/redis/v8

    chmod -R 777 /home/user
