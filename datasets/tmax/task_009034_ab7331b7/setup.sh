#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    # Create workspace and file
    mkdir -p /home/user/workspace
    cat << 'EOF' > /home/user/workspace/simulate_network.go
package main

import (
	"fmt"
	"sync"
)

func simulateODE(y0 float64, k float64, steps int, dt float64) float64 {
	y := y0
	for i := 0; i < steps; i++ {
		y = y - k*y*dt
	}
	return y
}

func main() {
	const N = 1000
	const steps = 1000
	const dt = 0.01

	var wg sync.WaitGroup
	var mu sync.Mutex
	var totalDensity float64

	for i := 1; i <= N; i++ {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			k := 0.1 + float64(id)*0.0001
			yFinal := simulateODE(100.0, k, steps, dt)

			mu.Lock()
			totalDensity += yFinal // BUG: Non-deterministic float reduction
			mu.Unlock()
		}(i)
	}

	wg.Wait()
	meanDensity := totalDensity / float64(N)
	fmt.Printf("%.15f\n", meanDensity)
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
