#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang binutils
    pip3 install pytest

    mkdir -p /home/user/bin
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/queries.log
1.0, 2.0, 3.0, 4.0, 5.0
10000.0, 10001.0, 10002.0
1000000000.0, 1000000001.0, 1000000002.0
999999998.0, 1000000000.0, 1000000002.0
5000000.5, 5000001.5
EOF

    cat << 'EOF' > /tmp/main.go
package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

func calculateSampleVariance(data []float32) float32 {
	if len(data) < 2 {
		return 0.0
	}
	var sum float32 = 0.0
	var sumSq float32 = 0.0
	for _, v := range data {
		sum += v
		sumSq += v * v
	}
	n := float32(len(data))
	return (sumSq - (sum*sum)/n) / (n - 1)
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: metric_calc <logfile>")
		return
	}
	file, err := os.Open(os.Args[1])
	if err != nil {
		fmt.Println("Error opening file:", err)
		return
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		parts := strings.Split(line, ",")
		var data []float32
		for _, p := range parts {
			val, _ := strconv.ParseFloat(strings.TrimSpace(p), 32)
			data = append(data, float32(val))
		}
		res := calculateSampleVariance(data)
		fmt.Printf("%.2f\n", res)
	}
}
EOF

    cd /tmp
    go build -o /home/user/bin/metric_calc main.go
    rm main.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
