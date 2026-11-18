#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gcc
    pip3 install pytest

    mkdir -p /home/user/go_src
    mkdir -p /home/user/build

    cat << 'EOF' > /home/user/go_src/aggregator.go
package main

import "C"
import (
	"strings"
	"sync"
)

//export GetIPs
func GetIPs() *C.char {
	var ips []string
	var mu sync.Mutex
	var wg sync.WaitGroup

	// Deterministic IP generation using goroutines and channels
	ipChan := make(chan string, 100)

	// Worker to collect IPs
	go func() {
		for ip := range ipChan {
			mu.Lock()
			ips = append(ips, ip)
			mu.Unlock()
		}
	}()

	// Generate 10.x.x.x
	wg.Add(1)
	go func() {
		defer wg.Done()
		for i := 0; i < 50; i++ {
			ipChan <- "10.5.0." + string(rune('0'+(i%10)))
		}
	}()

	// Generate 172.16.x.x to 172.31.x.x
	wg.Add(1)
	go func() {
		defer wg.Done()
		for i := 0; i < 30; i++ {
			ipChan <- "172.20.1.1"
		}
	}()

	// Generate 192.168.1.x
	wg.Add(1)
	go func() {
		defer wg.Done()
		for i := 0; i < 20; i++ {
			ipChan <- "192.168.1.100"
		}
	}()

	// Out of bounds
	wg.Add(1)
	go func() {
		defer wg.Done()
		for i := 0; i < 15; i++ {
			ipChan <- "192.168.2.100" // Not in 192.168.1.0/24
		}
	}()

	wg.Wait()
	close(ipChan)

	// Wait a tiny bit for the collector goroutine to finish processing
	// (In a real app we'd use another waitgroup for the consumer)

	return C.CString(strings.Join(ips, ","))
}

func main() {}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
