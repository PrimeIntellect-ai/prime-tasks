#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tar
    pip3 install pytest

    # Install Go 1.20
    wget https://go.dev/dl/go1.20.14.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.20.14.linux-amd64.tar.gz
    rm go1.20.14.linux-amd64.tar.gz
    export PATH=$PATH:/usr/local/go/bin

    # Create directories
    mkdir -p /home/user/data
    mkdir -p /home/user/src/mahalanobis

    # Generate kmer_counts.csv
    python3 -c "
import csv
import random
random.seed(42)
with open('/home/user/data/kmer_counts.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    for i in range(100):
        row = []
        for j in range(9):
            val = random.uniform(0, 1)
            if i < 50:
                val += 0.5
            row.append(round(val, 4))
        row.append(row[8]) # col 10 identical to col 9
        writer.writerow(row)
"

    # Create go.mod
    cat << 'EOF' > /home/user/src/mahalanobis/go.mod
module mahalanobis

go 1.20

require gonum.org/v1/gonum v0.14.0
EOF

    # Create main.go
    cat << 'EOF' > /home/user/src/mahalanobis/main.go
package main

import (
    "encoding/csv"
    "fmt"
    "log"
    "os"
    "strconv"

    "gonum.org/v1/gonum/mat"
    "gonum.org/v1/gonum/stat"
)

func main() {
    f, err := os.Open("/home/user/data/kmer_counts.csv")
    if err != nil {
        log.Fatal(err)
    }
    defer f.Close()

    records, err := csv.NewReader(f).ReadAll()
    if err != nil {
        log.Fatal(err)
    }

    n := len(records)
    p := len(records[0])
    data := mat.NewDense(n, p, nil)

    for i, row := range records {
        for j, val := range row {
            v, _ := strconv.ParseFloat(val, 64)
            data.Set(i, j, v)
        }
    }

    var cov mat.SymDense
    stat.CovarianceMatrix(&cov, data, nil)

    var inv mat.SymDense
    err = inv.Inverse(&cov)
    if err != nil {
        log.Fatalf("Matrix inversion failed: %v", err)
    }

    fmt.Println("Success")
}
EOF

    # Download dependencies
    cd /home/user/src/mahalanobis
    /usr/local/go/bin/go mod tidy

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
