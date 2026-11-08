#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/oracle.go
package main

import (
	"crypto/md5"
	"encoding/csv"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
)

func main() {
	reader := csv.NewReader(os.Stdin)
	// Read header
	_, err := reader.Read()
	if err != nil {
		return
	}

	seen := make(map[string]bool)
	type Record struct {
		Timestamp int64
		Metric    int64
	}
	var validRecords []Record

	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			continue
		}
		if len(record) != 3 {
			continue
		}

		// Drop if contains newline
		if strings.Contains(record[0], "\n") || strings.Contains(record[1], "\n") || strings.Contains(record[2], "\n") {
			continue
		}

		msg := record[1]
		hash := fmt.Sprintf("%x", md5.Sum([]byte(msg)))
		if seen[hash] {
			continue
		}
		seen[hash] = true

		ts, err := strconv.ParseInt(record[0], 10, 64)
		if err != nil {
			continue
		}
		metric, err := strconv.ParseInt(record[2], 10, 64)
		if err != nil {
			continue
		}

		validRecords = append(validRecords, Record{Timestamp: ts, Metric: metric})
	}

	if len(validRecords) == 0 {
		return
	}

	minBucket := validRecords[0].Timestamp / 10 * 10
	maxBucket := minBucket

	for _, r := range validRecords {
		b := r.Timestamp / 10 * 10
		if b < minBucket {
			minBucket = b
		}
		if b > maxBucket {
			maxBucket = b
		}
	}

	buckets := make(map[int64]int64)
	for _, r := range validRecords {
		b := r.Timestamp / 10 * 10
		buckets[b] += r.Metric
	}

	var bucketKeys []int64
	for b := minBucket; b <= maxBucket; b += 10 {
		bucketKeys = append(bucketKeys, b)
	}

	fmt.Println("bucket,sum,anomaly")
	var prevSum int64
	for i, b := range bucketKeys {
		sum := buckets[b]
		anomaly := 0
		if i > 0 && sum > prevSum+50 {
			anomaly = 1
		}
		fmt.Printf("%d,%d,%d\n", b, sum, anomaly)
		prevSum = sum
	}
}
EOF

    cd /app
    go build -o log_oracle oracle.go
    strip log_oracle
    rm oracle.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
