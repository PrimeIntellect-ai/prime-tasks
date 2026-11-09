#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/datasets

    # Generate deterministic datasets
    python3 -c '
import random
random.seed(42)
def gen(fname, mu, sigma, n):
    with open(fname, "w") as f:
        for _ in range(n):
            f.write(f"{random.gauss(mu, sigma)}\n")

gen("/home/user/datasets/exp1.csv", 10.05, 1.0, 100)
gen("/home/user/datasets/exp2.csv", 11.5, 1.0, 100)
gen("/home/user/datasets/exp3.csv", 8.2, 1.0, 100)
'

    cat << 'EOF' > /home/user/check_accuracy.go
package main

import (
	"bufio"
	"fmt"
	"math"
	"os"
	"strconv"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: check_accuracy <csv_file>")
		os.Exit(1)
	}

	file, err := os.Open(os.Args[1])
	if err != nil {
		panic(err)
	}
	defer file.Close()

	var data []float64
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		val, _ := strconv.ParseFloat(scanner.Text(), 64)
		data = append(data, val)
	}

	n := float64(len(data))
	sum := 0.0
	for _, v := range data {
		sum += v
	}
	mean := sum / n

	sqSum := 0.0
	for _, v := range data {
		sqSum += (v - mean) * (v - mean)
	}
	stdDev := math.Sqrt(sqSum / (n - 1)) // sample standard deviation

	target := 10.0

	// TODO: Calculate 95% CI and print PASS or FAIL
	// lowerBound := ...
	// upperBound := ...

	// Print exactly "PASS" or "FAIL"
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
