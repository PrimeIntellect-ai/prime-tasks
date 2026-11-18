#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/aggregator

cat << 'EOF' > /home/user/aggregator/transactions.log
1000000.10
1000000.20
1000000.15
1000000.25
1000000.10
CORRUPT_RECORD
1000000.30
1000000.05
1000000.15
1000000.20
1000000.10
EOF

cat << 'EOF' > /home/user/aggregator/main.go
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"strings"
)

type Metrics struct {
	Count    int     `json:"count"`
	Mean     float64 `json:"mean"`
	Variance float64 `json:"variance"`
}

func main() {
	file, err := os.Open("transactions.log")
	if err != nil {
		panic(err)
	}
	defer file.Close()

	var sum, sumSq float64
	var count int

	var recentValues *[]float64
	vals := make([]float64, 0)
	recentValues = &vals

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "CORRUPT_RECORD" {
			recentValues = nil // Causes panic on next iteration
			continue
		}

		val, err := strconv.ParseFloat(line, 64)
		if err != nil {
			continue
		}

		*recentValues = append(*recentValues, val)

		sum += val
		sumSq += val * val
		count++
	}

	mean := sum / float64(count)
	// Naive variance prone to catastrophic cancellation
	variance := (sumSq - (sum*sum)/float64(count)) / float64(count)

	m := Metrics{
		Count:    count,
		Mean:     mean,
		Variance: variance,
	}

	out, _ := json.MarshalIndent(m, "", "  ")
	fmt.Println(string(out))
}
EOF

chmod -R 777 /home/user
