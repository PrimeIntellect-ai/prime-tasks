#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/container_metrics.log
100000000.01
100000000.02
100000000.03
100000000.04
100000000.05
EOF

    cat << 'EOF' > /home/user/aggregator.go
package main

import (
	"bufio"
	"fmt"
	"math"
	"os"
	"strconv"
)

func main() {
	file, err := os.Open("/home/user/container_metrics.log")
	if err != nil {
		panic(err)
	}
	defer file.Close()

	var sum float64
	var sumSq float64
	var count float64

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		val, _ := strconv.ParseFloat(scanner.Text(), 64)
		sum += val
		sumSq += val * val
		count++
	}

	mean := sum / count
	variance := (sumSq / count) - (mean * mean)

	// Panic on numerical instability
	if variance < 0 {
		panic(fmt.Sprintf("Fatal error: negative variance calculated: %f. Stack trace: main.main() /home/user/aggregator.go:34", variance))
	}

	stddev := math.Sqrt(variance)

	out, err := os.Create("/home/user/result.txt")
	if err != nil {
		panic(err)
	}
	defer out.Close()
	fmt.Fprintf(out, "%.6f\n", stddev)
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
