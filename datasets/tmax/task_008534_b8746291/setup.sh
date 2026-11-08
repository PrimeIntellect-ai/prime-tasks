#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create synthetic data
    cat << 'EOF' > generate_data.py
import csv
import random
import math

random.seed(42)
with open('embeddings.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    for i in range(100):
        label = 0 if i < 50 else 1
        # Feature 1: Highly correlated with label, but with a shift
        f1 = random.gauss(label * 5, 1.0)
        # Feature 2: Noise
        f2 = random.gauss(0, 5.0)
        writer.writerow([f1, f2, label])
EOF
    python3 generate_data.py

    # Create the buggy Go program
    cat << 'EOF' > pipeline.go
package main

import (
	"encoding/csv"
	"fmt"
	"math"
	"os"
	"strconv"
)

type Sample struct {
	Features []float64
	Label    int
}

func main() {
	file, err := os.Open("embeddings.csv")
	if err != nil {
		panic(err)
	}
	defer file.Close()

	reader := csv.NewReader(file)
	records, err := reader.ReadAll()
	if err != nil {
		panic(err)
	}

	var data []Sample
	for _, rec := range records {
		f1, _ := strconv.ParseFloat(rec[0], 64)
		f2, _ := strconv.ParseFloat(rec[1], 64)
		label, _ := strconv.Atoi(rec[2])
		data = append(data, Sample{Features: []float64{f1, f2}, Label: label})
	}

	// DATA LEAKAGE: Calculate mean and stddev on ALL data
	numFeatures := 2
	means := make([]float64, numFeatures)
	stds := make([]float64, numFeatures)

	for _, d := range data {
		for i := 0; i < numFeatures; i++ {
			means[i] += d.Features[i]
		}
	}
	for i := 0; i < numFeatures; i++ {
		means[i] /= float64(len(data))
	}

	for _, d := range data {
		for i := 0; i < numFeatures; i++ {
			diff := d.Features[i] - means[i]
			stds[i] += diff * diff
		}
	}
	for i := 0; i < numFeatures; i++ {
		stds[i] = math.Sqrt(stds[i] / float64(len(data)))
	}

	// Normalize ALL data
	for j := range data {
		for i := 0; i < numFeatures; i++ {
			if stds[i] != 0 {
				data[j].Features[i] = (data[j].Features[i] - means[i]) / stds[i]
			}
		}
	}

	// Split data: 80 train, 20 test
	train := data[:80]
	test := data[80:]

	// Train Nearest Centroid
	centroids := make(map[int][]float64)
	counts := make(map[int]int)

	for _, t := range train {
		if _, ok := centroids[t.Label]; !ok {
			centroids[t.Label] = make([]float64, numFeatures)
		}
		for i := 0; i < numFeatures; i++ {
			centroids[t.Label][i] += t.Features[i]
		}
		counts[t.Label]++
	}

	for label, count := range counts {
		for i := 0; i < numFeatures; i++ {
			centroids[label][i] /= float64(count)
		}
	}

	// Evaluate
	correct := 0
	for _, t := range test {
		bestLabel := -1
		minDist := math.MaxFloat64
		for label, centroid := range centroids {
			dist := 0.0
			for i := 0; i < numFeatures; i++ {
				diff := t.Features[i] - centroid[i]
				dist += diff * diff
			}
			if dist < minDist {
				minDist = dist
				bestLabel = label
			}
		}
		if bestLabel == t.Label {
			correct++
		}
	}

	accuracy := float64(correct) / float64(len(test))
	fmt.Printf("Accuracy: %f\n", accuracy)
}
EOF

    # Initialize go module
    go mod init pipeline

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
