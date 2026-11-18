#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/service.go
package main

import (
	"context"
	"encoding/binary"
	"fmt"
	"io"
	"os"
	"sync"
	"time"
)

func processPayload(ctx context.Context, data []byte, wg *sync.WaitGroup) {
	defer wg.Done()
	if len(data) < 8 {
		return
	}

	val := float64(binary.LittleEndian.Uint64(data[:8]))

	// Decay loop
	for val > 0.001 {
		val -= 0.1
        // BUG: no ctx.Done() check
        // BUG: if val is large enough (e.g. 1e16), val -= 0.1 does nothing
	}
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: service <payload>")
		os.Exit(1)
	}
	f, err := os.Open(os.Args[1])
	if err != nil {
		os.Exit(1)
	}
	defer f.Close()
	data, _ := io.ReadAll(f)

	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()

	var wg sync.WaitGroup
	for i := 0; i < len(data); i += 8 {
		end := i + 8
		if end > len(data) {
			break
		}
		wg.Add(1)
		go processPayload(ctx, data[i:end], &wg)
	}

	done := make(chan struct{})
	go func() {
		wg.Wait()
		close(done)
	}()

	select {
	case <-done:
		fmt.Println("Success")
		os.Exit(0)
	case <-time.After(1 * time.Second):
		fmt.Println("Watchdog: Goroutine leak detected!")
		os.Exit(1)
	}
}
EOF

    python3 -c "
import struct
# 10 normal floats (e.g., 5.0)
normal = struct.pack('<d', 5.0) * 10
# 1 bad float (1e16)
bad = struct.pack('<d', 1e16)
# 10 normal floats
normal2 = struct.pack('<d', 2.0) * 10

with open('/home/user/payload.bin', 'wb') as f:
    f.write(normal + bad + normal2)
"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
