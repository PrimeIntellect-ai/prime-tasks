#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gawk
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Generate reads.txt with 10,000 float values (harmonic series for precision testing)
    awk 'BEGIN { for(i=1; i<=10000; i++) printf "%.12f\n", 1.0/i }' > /home/user/reads.txt

    # Create the buggy Go script
    cat << 'EOF' > /home/user/kmer_density.go
package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"sync"
)

func main() {
	file, err := os.Open("/home/user/reads.txt")
	if err != nil {
		panic(err)
	}
	defer file.Close()

	var wg sync.WaitGroup
	var mu sync.Mutex
	var totalDensity float64

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		val, _ := strconv.ParseFloat(scanner.Text(), 64)
		wg.Add(1)
		go func(v float64) {
			defer wg.Done()
			// simulated feature scaling
			processed := v * 0.123456789
			mu.Lock()
			totalDensity += processed
			mu.Unlock()
		}(val)
	}
	wg.Wait()
	fmt.Printf("%.12f\n", totalDensity)
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
