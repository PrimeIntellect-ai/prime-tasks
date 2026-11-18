#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest matplotlib

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/integrate.go
// /home/user/integrate.go
package main

import (
	"fmt"
	"math"
	"sync"
)

func signal(x float64) float64 {
	sum := 0.0
	// Fourier series approximation
	for k := 1.0; k <= 100.0; k++ {
		sum += math.Sin(k*x) / k
	}
	return sum
}

func main() {
	N := 10000000
	G := 16
	a, b := 0.0, math.Pi
	dx := (b - a) / float64(N)

	ch := make(chan float64, G)
	var wg sync.WaitGroup

	chunk := N / G
	for i := 0; i < G; i++ {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			startIdx := id * chunk
			endIdx := startIdx + chunk
			if id == G-1 {
				endIdx = N
			}

			partial := 0.0
			for j := startIdx; j < endIdx; j++ {
				x1 := a + float64(j)*dx
				x2 := a + float64(j+1)*dx
				partial += (signal(x1) + signal(x2)) / 2.0 * dx
			}
			ch <- partial
		}(i)
	}

	go func() {
		wg.Wait()
		close(ch)
	}()

	total := 0.0
	// BUG: Non-deterministic order of floating-point reduction
	for p := range ch {
		total += p
	}

	fmt.Printf("%.15f\n", total)
}
EOF

    chmod -R 777 /home/user
