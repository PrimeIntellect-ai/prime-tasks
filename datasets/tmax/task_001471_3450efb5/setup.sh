#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/nanofit/data

    cat << 'EOF' > /home/user/nanofit/data/signals.csv
id,decay_rate,initial_signal,time_end
seq1,5.0,100.0,2.0
seq2,2.5,50.0,4.0
seq3,10.0,200.0,1.0
EOF

    cat << 'EOF' > /home/user/nanofit/ode.go
package main

// IntegrateODE solves dy/dt = -k * y using the Euler method.
// Returns the value of y at t = tEnd.
func IntegrateODE(k, y0, tEnd float64) float64 {
	y := y0
	t := 0.0
	dt := 0.1

	for t < tEnd {
		// Euler step
		y = y - dt*k*y
		t += dt

		// BUG: Faulty step size adaptation that causes divergence for stiff equations
		dt = dt * 1.5
	}
	return y
}
EOF

    cat << 'EOF' > /home/user/nanofit/ode_test.go
package main

import (
	"math"
	"testing"
)

func TestIntegrateODE(t *testing.T) {
	// For dy/dt = -5 * y, y(0) = 100, tEnd = 2.0
	// Exact solution: 100 * exp(-10) approx 0.00453999
	// With dt=0.001 Euler approximation gives ~0.004517
	result := IntegrateODE(5.0, 100.0, 2.0)

	if math.IsNaN(result) || math.IsInf(result, 0) {
		t.Fatalf("Integration diverged: result is %v", result)
	}

	expected := 0.004517
	tolerance := 0.0001

	if math.Abs(result-expected) > tolerance {
		t.Fatalf("Regression test failed: expected approx %f, got %f", expected, result)
	}
}
EOF

    cat << 'EOF' > /home/user/nanofit/main.go
package main

import (
	"encoding/csv"
	"flag"
	"fmt"
	"os"
	"strconv"
)

func main() {
	inputPath := flag.String("input", "", "Input CSV file")
	outputPath := flag.String("output", "", "Output CSV file")
	flag.Parse()

	if *inputPath == "" || *outputPath == "" {
		fmt.Println("Input and output paths are required")
		os.Exit(1)
	}

	inFile, err := os.Open(*inputPath)
	if err != nil {
		panic(err)
	}
	defer inFile.Close()

	reader := csv.NewReader(inFile)
	records, err := reader.ReadAll()
	if err != nil {
		panic(err)
	}

	outFile, err := os.Create(*outputPath)
	if err != nil {
		panic(err)
	}
	defer outFile.Close()

	writer := csv.NewWriter(outFile)
	defer writer.Flush()

	writer.Write([]string{"id", "final_signal"})

	for i, record := range records {
		if i == 0 {
			continue // skip header
		}
		id := record[0]
		k, _ := strconv.ParseFloat(record[1], 64)
		y0, _ := strconv.ParseFloat(record[2], 64)
		tEnd, _ := strconv.ParseFloat(record[3], 64)

		res := IntegrateODE(k, y0, tEnd)
		writer.Write([]string{id, fmt.Sprintf("%.6f", res)})
	}
}
EOF

    cd /home/user/nanofit
    go mod init nanofit

    chmod -R 777 /home/user
