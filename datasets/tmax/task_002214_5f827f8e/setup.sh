#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make openssl golang-go binutils
pip3 install pytest

# Create user
useradd -m -s /bin/bash user || true
touch /home/user/.bashrc

# Build /app/bench
mkdir -p /app
cat << 'EOF' > /tmp/bench.go
package main

import (
	"fmt"
	"net"
	"os"
	"time"
)

func main() {
	if len(os.Args) < 3 {
		fmt.Println("Usage: bench <host> <port>")
		os.Exit(1)
	}
	addr := os.Args[1] + ":" + os.Args[2]
	req := []byte("GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")

	start := time.Now()
	duration := 5 * time.Second
	concurrency := 100
	ch := make(chan int)

	for i := 0; i < concurrency; i++ {
		go func() {
			count := 0
			for time.Since(start) < duration {
				conn, err := net.DialTimeout("tcp", addr, 1*time.Second)
				if err == nil {
					conn.Write(req)
					buf := make([]byte, 128)
					conn.Read(buf)
					conn.Close()
					count++
				} else {
					time.Sleep(5 * time.Millisecond)
				}
			}
			ch <- count
		}()
	}

	total := 0
	for i := 0; i < concurrency; i++ {
		total += <-ch
	}

	rps := float64(total) / time.Since(start).Seconds()
	fmt.Printf("Requests per second: %.2f\n", rps)
}
EOF

go build -o /app/bench /tmp/bench.go
strip -s /app/bench
rm /tmp/bench.go
chmod +x /app/bench

chmod -R 777 /home/user
