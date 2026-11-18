#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > generate_data.py
import csv
import math

A_true = 5.0
k_true = 0.2
B_true = 1.0

with open('spectra.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["time", "intensity"])
    for i in range(101):
        t = i * 0.1
        intensity = A_true * math.exp(-k_true * t) + B_true
        writer.writerow([f"{t:.2f}", f"{intensity:.6f}"])
EOF
    python3 generate_data.py
    rm generate_data.py

    cat << 'EOF' > fit.go
package main

import (
	"encoding/csv"
	"fmt"
	"math"
	"os"
	"strconv"
)

type Point struct {
	t float64
	y float64
}

func main() {
	file, err := os.Open("spectra.csv")
	if err != nil {
		panic(err)
	}
	defer file.Close()

	reader := csv.NewReader(file)
	records, err := reader.ReadAll()
	if err != nil {
		panic(err)
	}

	var data []Point
	for i, record := range records {
		if i == 0 {
			continue // skip header
		}
		t, _ := strconv.ParseFloat(record[0], 64)
		y, _ := strconv.ParseFloat(record[1], 64)
		data = append(data, Point{t, y})
	}

	// Initial guesses
	A := 1.0
	k := 0.1
	B := 0.5

	// DIVERGING STEP SIZE: alpha is too large
	alpha := 0.5
	epochs := 10000

	for epoch := 0; epoch < epochs; epoch++ {
		var gradA, gradK, gradB float64
		n := float64(len(data))

		for _, p := range data {
			pred := A*math.Exp(-k*p.t) + B
			err := pred - p.y

			gradA += (2.0 / n) * err * math.Exp(-k*p.t)
			gradK += (2.0 / n) * err * A * math.Exp(-k*p.t) * (-p.t)
			gradB += (2.0 / n) * err
		}

		A -= alpha * gradA
		k -= alpha * gradK
		B -= alpha * gradB
	}

	fmt.Printf("Fitted parameters:\nA = %.2f\nk = %.2f\nB = %.2f\n", A, k, B)
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
