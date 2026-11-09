#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget
    pip3 install pytest

    # Install Go 1.21+ to satisfy gonum requirements
    wget https://go.dev/dl/go1.21.6.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz
    rm go1.21.6.linux-amd64.tar.gz
    export PATH=/usr/local/go/bin:$PATH

    mkdir -p /home/user/sim

    cat << 'EOF' > /home/user/raw_data.txt
1001 2.0 3.5 5.5
1002 2.1 3.4 5.5
1003 1.9 3.6 5.5
1004 2.2 3.3 5.5
1005 2.0 3.5 5.5
1006 1.8 3.7 5.5
1007 2.3 3.2 5.5
1008 1.9 3.5 5.4
1009 2.1 3.6 5.7
1010 2.0 3.4 5.4
EOF

    cat << 'EOF' > /home/user/sim/main.go
package main

import (
	"encoding/csv"
	"flag"
	"fmt"
	"log"
	"math"
	"math/rand"
	"os"
	"strconv"

	"gonum.org/v1/gonum/mat"
	"gonum.org/v1/gonum/stat"
)

func main() {
	nFlag := flag.Int("n", 1000, "number of samples")
	flag.Parse()

	file, err := os.Open("/home/user/processed.csv")
	if err != nil {
		log.Fatalf("failed opening file: %s", err)
	}
	defer file.Close()

	reader := csv.NewReader(file)
	records, err := reader.ReadAll()
	if err != nil {
		log.Fatalf("failed reading csv: %s", err)
	}

	rows := len(records)
	cols := 3
	data := make([]float64, rows*cols)
	for i, row := range records {
		for j, val := range row {
			v, _ := strconv.ParseFloat(val, 64)
			data[i*cols+j] = v
		}
	}

	X := mat.NewDense(rows, cols, data)
	cov := mat.NewSymDense(cols, nil)
	stat.CovarianceMatrix(cov, X, nil)

	// CHOLESKY FACTORIZATION
	var chol mat.Cholesky
	ok := chol.Factorize(cov)
	if !ok {
		log.Fatalf("Cholesky factorization failed! Matrix is likely singular.")
	}

	// Generate samples
	var lower mat.Dense
	chol.LTo(&lower)

	rnd := rand.New(rand.NewSource(42))
	sumC := 0.0

	for i := 0; i < *nFlag; i++ {
		z := mat.NewVecDense(cols, []float64{rnd.NormFloat64(), rnd.NormFloat64(), rnd.NormFloat64()})
		sample := mat.NewVecDense(cols, nil)
		sample.MulVec(&lower, z)

		// Add mean back (mean of C is ~5.5)
		sumC += sample.AtVec(2) + 5.5
	}

	fmt.Printf("%f\n", sumC/float64(*nFlag))
}
EOF

    cd /home/user/sim
    go mod init sim
    go get gonum.org/v1/gonum/mat
    go get gonum.org/v1/gonum/stat

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
