#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tar git
    pip3 install pytest

    # Install Go 1.21.6 to support recent gonum packages
    wget https://go.dev/dl/go1.21.6.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz
    rm go1.21.6.linux-amd64.tar.gz
    export PATH=/usr/local/go/bin:$PATH

    mkdir -p /home/user/data_prep
    cd /home/user/data_prep

    # Initialize Go module
    go mod init data_prep
    go get gonum.org/v1/gonum/mat

    # Create the near-singular matrix CSV
    cat << 'EOF' > /home/user/data_prep/matrix.csv
5.0, 11.0, 17.0, 23.0
11.0, 25.0, 39.0, 53.0
17.0, 39.0, 61.0, 83.0
23.0, 53.0, 83.0, 113.0
EOF

    # Create the failing main.go
    cat << 'EOF' > /home/user/data_prep/main.go
package main

import (
	"encoding/csv"
	"fmt"
	"log"
	"os"
	"strconv"

	"gonum.org/v1/gonum/mat"
)

func main() {
	// Read the matrix from CSV
	file, err := os.Open("matrix.csv")
	if err != nil {
		log.Fatal(err)
	}
	defer file.Close()

	reader := csv.NewReader(file)
	records, err := reader.ReadAll()
	if err != nil {
		log.Fatal(err)
	}

	rows := len(records)
	cols := len(records[0])
	data := make([]float64, rows*cols)

	for i, row := range records {
		for j, val := range row {
			v, _ := strconv.ParseFloat(val, 64)
			data[i*cols+j] = v
		}
	}

	cMatrix := mat.NewDense(rows, cols, data)

	// Attempt Cholesky Decomposition
	var chol mat.Cholesky
	ok := chol.Factorize(cMatrix)
	if !ok {
		log.Fatal("Cholesky decomposition failed: matrix is not positive definite!")
	}

	fmt.Println("Success!")
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/data_prep
    chmod -R 777 /home/user
