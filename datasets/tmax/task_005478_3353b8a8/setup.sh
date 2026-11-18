#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go python3-numpy
    pip3 install pytest

    mkdir -p /home/user/data_processor

    cat << 'EOF' > /home/user/data_processor/main.go
package main

import (
	"encoding/csv"
	"fmt"
	"math"
	"os"
	"strconv"
)

type Stats struct {
	Count float32
	Sum   float32
	SumSq float32
}

func (s *Stats) Add(val float32) {
	s.Count++
	s.Sum += val
	s.SumSq += val * val
}

func (s *Stats) StdDev() float64 {
	mean := s.Sum / s.Count
	// Catastrophic cancellation happens here due to float32 precision limits
	variance := (s.SumSq / s.Count) - (mean * mean)
	return math.Sqrt(float64(variance))
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: go run main.go <file.csv>")
		os.Exit(1)
	}

	file, err := os.Open(os.Args[1])
	if err != nil {
		panic(err)
	}
	defer file.Close()

	reader := csv.NewReader(file)
	records, err := reader.ReadAll()
	if err != nil {
		panic(err)
	}

	stats := &Stats{}
	for _, record := range records {
		val, _ := strconv.ParseFloat(record[0], 32)
		stats.Add(float32(val))
	}

	fmt.Printf("%.6f\n", stats.StdDev())
}
EOF

    cat << 'EOF' > /tmp/generate_data.py
import struct
import math
import numpy as np

with open("/home/user/data_processor/dataset.csv", "w") as f:
    for i in range(5000):
        f.write("10000.0\n")
        f.write("10000.1\n")

count = np.float32(0.0)
sum_val = np.float32(0.0)
sum_sq = np.float32(0.0)

failing_row = -1
for i in range(1, 10001):
    val = np.float32(10000.0 if i % 2 != 0 else 10000.1)
    count += np.float32(1.0)
    sum_val += val
    sum_sq += val * val

    mean = sum_val / count
    variance = (sum_sq / count) - (mean * mean)

    if variance < 0 and failing_row == -1:
        failing_row = i

expected_output = "0.050000"

with open("/tmp/truth.txt", "w") as f:
    f.write(f"FAILING_ROW={failing_row}\n")
    f.write(f"EXPECTED={expected_output}\n")
EOF

    python3 /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
