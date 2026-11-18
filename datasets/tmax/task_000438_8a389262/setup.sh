#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/data /home/user/pipeline

    cat << 'EOF' > /home/user/data/raw_measurements.csv
id,measurement
1,150
2,300
3,45
4,120
5,280
EOF

    cat << 'EOF' > /home/user/pipeline/process.go
package main

import (
	"encoding/csv"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strconv"
)

type Record struct {
	ID    int     `json:"id"`
	Value float64 `json:"value"`
}

// Normalize applies min-max normalization
func Normalize(data []float64) []float64 {
	if len(data) == 0 {
		return nil
	}
	min := data[0]
	max := data[0]
	for _, v := range data {
		if v < min {
			min = v
		}
		if v > max {
			max = v
		}
	}

	result := make([]float64, len(data))
	if min == max {
		for i := range result {
			result[i] = 0.0
		}
		return result
	}

	for i, v := range data {
		// BUG: Integer division if not careful, or simulated precision bug
		// We'll simulate the bug by casting to int before division
		result[i] = float64(int(v-min) / int(max-min))
	}
	return result
}

func main() {
	f, err := os.Open("/home/user/data/raw_measurements.csv")
	if err != nil {
		panic(err)
	}
	defer f.Close()

	r := csv.NewReader(f)
	_, _ = r.Read() // skip header

	var ids []int
	var values []float64

	for {
		record, err := r.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			panic(err)
		}
		id, _ := strconv.Atoi(record[0])
		val, _ := strconv.ParseFloat(record[1], 64)
		ids = append(ids, id)
		values = append(values, val)
	}

	normalized := Normalize(values)

	var output []Record
	for i := range ids {
		output = append(output, Record{ID: ids[i], Value: normalized[i]})
	}

	outF, err := os.Create("/home/user/data/processed.json")
	if err != nil {
		panic(err)
	}
	defer outF.Close()

	enc := json.NewEncoder(outF)
	enc.SetIndent("", "  ")
	enc.Encode(output)
	fmt.Println("Processed data written.")
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
