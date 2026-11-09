#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create sequences.csv
    cat << 'EOF' > sequences.csv
Score
1.23
0.45
2.11
-0.56
0.88
1.02
-1.22
0.05
1.44
0.77
EOF
    for i in {1..10}; do cat sequences.csv >> temp.csv; done
    mv temp.csv sequences.csv

    # Create mcmc.go
    cat << 'EOF' > mcmc.go
package main

import (
	"bufio"
	"encoding/csv"
	"fmt"
	"math"
	"math/rand"
	"os"
	"strconv"
	"sync"
)

type ChunkResult struct {
	ChunkID int
	Val     float64
}

func LogLikelihood(mu float64, data []float64) float64 {
	numChunks := 10
	chunkSize := len(data) / numChunks
	ch := make(chan ChunkResult, numChunks)
	var wg sync.WaitGroup

	for i := 0; i < numChunks; i++ {
		wg.Add(1)
		go func(chunkID int) {
			defer wg.Done()
			start := chunkID * chunkSize
			end := start + chunkSize
			if chunkID == numChunks-1 {
				end = len(data)
			}

			sum := 0.0
			for _, val := range data[start:end] {
				// Log-likelihood for normal dist: -(val - mu)^2
				sum -= (val - mu) * (val - mu)
			}
			ch <- ChunkResult{ChunkID: chunkID, Val: sum}
		}(i)
	}

	wg.Wait()
	close(ch)

	totalLL := 0.0
	// BUG: Non-deterministic floating point reduction order
	for res := range ch {
		totalLL += res.Val
	}

	return totalLL
}

func main() {
	rand.Seed(42)

	file, err := os.Open("sequences.csv")
	if err != nil {
		panic(err)
	}
	defer file.Close()

	var data []float64
	scanner := bufio.NewScanner(file)
	scanner.Scan() // skip header
	for scanner.Scan() {
		val, _ := strconv.ParseFloat(scanner.Text(), 64)
		data = append(data, val)
	}

	out, err := os.Create("trace.csv")
	if err != nil {
		panic(err)
	}
	defer out.Close()
	writer := csv.NewWriter(out)
	writer.Write([]string{"Iteration", "Mu", "LogLikelihood"})

	mu := 0.0
	currentLL := LogLikelihood(mu, data)

	writer.Write([]string{"0", fmt.Sprintf("%.6f", mu), fmt.Sprintf("%.6f", currentLL)})

	for i := 1; i <= 100; i++ {
		propMu := mu + rand.NormFloat64()*0.1
		propLL := LogLikelihood(propMu, data)

		if propLL > currentLL || math.Log(rand.Float64()) < (propLL-currentLL) {
			mu = propMu
			currentLL = propLL
		}

		writer.Write([]string{strconv.Itoa(i), fmt.Sprintf("%.6f", mu), fmt.Sprintf("%.6f", currentLL)})
	}
	writer.Flush()
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
