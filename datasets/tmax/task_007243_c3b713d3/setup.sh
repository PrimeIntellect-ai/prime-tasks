#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/network_data.txt
100000.1
100000.2
100000.3
EOF

    cat << 'EOF' > /home/user/log_analyzer.go
package main

import (
	"bufio"
	"fmt"
	"math"
	"os"
	"strconv"
)

func main() {
	file, err := os.Open("/home/user/network_data.txt")
	if err != nil {
		panic(err)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	var sum, sumSq float32
	var count float32

	for scanner.Scan() {
		val, _ := strconv.ParseFloat(scanner.Text(), 32)
		v := float32(val)
		sum += v
		sumSq += v * v
		count++
	}

	mean := sum / count
	variance := (sumSq / count) - (mean * mean)

	if variance < 0 {
		panic(fmt.Sprintf("statistical anomaly: negative variance detected: %f", variance))
	}

	stddev := math.Sqrt(float64(variance))
	fmt.Printf("%.4f\n", stddev)
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
