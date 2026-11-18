#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cd /home/user

    cat << 'EOF' > raw_spectra.txt
ObservationID|Wavelength|Intensity
obs001|498.0|1.2
obs002|498.5|-0.5
obs003|499.0|2.1
obs004|499.5|5.4
obs005|500.0|NaN
obs006|500.0|10.2
obs007|500.5|8.1
obs008|501.0|3.2
obs009|501.5|1.5
obs010|502.0|-1.0
obs011|502.5|1.1
EOF

    cat << 'EOF' > mcmc_fitter.go
package main

import (
	"encoding/csv"
	"fmt"
	"os"
	"strconv"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: fitter <csv_file>")
		os.Exit(1)
	}

	file, err := os.Open(os.Args[1])
	if err != nil {
		fmt.Println("Error opening file:", err)
		os.Exit(1)
	}
	defer file.Close()

	reader := csv.NewReader(file)
	records, err := reader.ReadAll()
	if err != nil {
		fmt.Println("Error reading CSV:", err)
		os.Exit(1)
	}

	// Mocking an MCMC fit that deterministically uses the sum of intensities
	// to generate pseudo-parameters to ensure easy verification.
	sumW, sumI := 0.0, 0.0
	for _, rec := range records {
		if len(rec) != 2 {
			continue
		}
		w, _ := strconv.ParseFloat(rec[0], 64)
		i, _ := strconv.ParseFloat(rec[1], 64)
		sumW += w
		sumI += i
	}

	// Pseudo-MCMC final posteriors
	fmt.Printf("MCMC chain finished (10000 iterations)\n")
	fmt.Printf("Amplitude: %.2f\n", sumI*0.5)
	fmt.Printf("Center: %.2f\n", sumW/float64(len(records)))
	fmt.Printf("Width: %.2f\n", 1.25)
	fmt.Printf("Background: %.2f\n", 1.05)
}
EOF

    chmod -R 777 /home/user
