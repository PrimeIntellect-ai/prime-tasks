#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/payload.dat
113731322b212b2d37316226302d3232273062212d2c2c2721362b2c2562362d620110622336621012116c126c1313116c1a176c620b2c2b362b2336276231273337272c21276c
EOF

    cat << 'EOF' > /home/user/dropper.go
package main

import (
	"encoding/hex"
	"fmt"
	"io/ioutil"
	"sync"
)

func main() {
	data, err := ioutil.ReadFile("/home/user/payload.dat")
	if err != nil {
		panic(err)
	}

	decoded, _ := hex.DecodeString(string(data))

	chunkSize := 16
	chunks := make(map[int][]byte)
	var wg sync.WaitGroup
	var mu sync.Mutex

	for i := 0; i < len(decoded); i += chunkSize {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			end := idx + chunkSize
			if end > len(decoded) {
				end = len(decoded)
			}
			chunk := decoded[idx:end]
			for j := range chunk {
				chunk[j] ^= 0x42
			}
			mu.Lock()
			chunks[idx] = chunk
			mu.Unlock()
		}(i)
	}
	wg.Wait()

	var out []byte
	// The bug: iterating over a map in Go is non-deterministic,
	// causing the decrypted chunks to be appended out-of-order.
	for _, chunk := range chunks {
		out = append(out, chunk...)
	}

	ioutil.WriteFile("/home/user/decoded.dat", out, 0644)
	fmt.Println("Decoded payload written to decoded.dat")
}
EOF

    chmod -R 777 /home/user
