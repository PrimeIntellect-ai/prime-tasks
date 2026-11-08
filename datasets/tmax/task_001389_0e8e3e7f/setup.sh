#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/csv_processor
    cd /home/user/csv_processor
    go mod init processor

    cat << 'EOF' > dataset.csv
ID,F1,F2,F3,Split
1,10.0,20.0,30.0,train
2,12.0,22.0,28.0,train
3,8.0,18.0,32.0,train
4,100.0,200.0,300.0,test
EOF

    cat << 'EOF' > main.go
package main

import (
	"encoding/csv"
	"fmt"
	"math"
	"os"
	"strconv"
)

type Row struct {
	ID    string
	F1    float64
	F2    float64
	F3    float64
	Split string
}

func main() {
	file, err := os.Open("dataset.csv")
	if err != nil {
		panic(err)
	}
	defer file.Close()

	reader := csv.NewReader(file)
	records, err := reader.ReadAll()
	if err != nil {
		panic(err)
	}

	var data []Row
	for i, rec := range records {
		if i == 0 {
			continue
		}
		f1, _ := strconv.ParseFloat(rec[1], 64)
		f2, _ := strconv.ParseFloat(rec[2], 64)
		f3, _ := strconv.ParseFloat(rec[3], 64)
		data = append(data, Row{ID: rec[0], F1: f1, F2: f2, F3: f3, Split: rec[4]})
	}

	// BUG: Calculating mean on ALL data
	sumF1, sumF2, sumF3 := 0.0, 0.0, 0.0
	for _, d := range data {
		sumF1 += d.F1
		sumF2 += d.F2
		sumF3 += d.F3
	}
	n := float64(len(data))
	meanF1 := sumF1 / n
	meanF2 := sumF2 / n
	meanF3 := sumF3 / n

	// BUG: Calculating stddev on ALL data
	var sqDiffF1, sqDiffF2, sqDiffF3 float64
	for _, d := range data {
		sqDiffF1 += (d.F1 - meanF1) * (d.F1 - meanF1)
		sqDiffF2 += (d.F2 - meanF2) * (d.F2 - meanF2)
		sqDiffF3 += (d.F3 - meanF3) * (d.F3 - meanF3)
	}
	stdF1 := math.Sqrt(sqDiffF1 / (n - 1))
	stdF2 := math.Sqrt(sqDiffF2 / (n - 1))
	stdF3 := math.Sqrt(sqDiffF3 / (n - 1))

	outFile, err := os.Create("processed.csv")
	if err != nil {
		panic(err)
	}
	defer outFile.Close()

	writer := csv.NewWriter(outFile)
	defer writer.Flush()

	writer.Write(records[0]) // Header

	for _, d := range data {
		row := []string{
			d.ID,
			fmt.Sprintf("%.4f", (d.F1-meanF1)/stdF1),
			fmt.Sprintf("%.4f", (d.F2-meanF2)/stdF2),
			fmt.Sprintf("%.4f", (d.F3-meanF3)/stdF3),
			d.Split,
		}
		writer.Write(row)
	}
}
EOF

    chmod -R 777 /home/user
