#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang ffmpeg
pip3 install pytest

mkdir -p /app
ffmpeg -f lavfi -i testsrc=duration=5:size=320x240:rate=30 -c:v libx264 -y /app/etl_stream.mp4

cat << 'EOF' > /app/oracle.go
package main

import (
	"bufio"
	"fmt"
	"math"
	"os"
	"sort"
	"strconv"
	"strings"
)

type Record struct {
	AlignedTime float64
	Type        string
	Size        int
	RetryID     int
	Order       int
}

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	records := make(map[string]Record)
	orderCounter := 0

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		parts := strings.Split(line, ",")
		if len(parts) != 4 {
			continue
		}

		timestamp, _ := strconv.ParseFloat(parts[0], 64)
		size, _ := strconv.Atoi(parts[1])
		typ := strings.ToLower(parts[2])
		retryID, _ := strconv.Atoi(parts[3])

		aligned := math.Round(timestamp*2) / 2
		key := fmt.Sprintf("%.1f_%s", aligned, typ)

		newRec := Record{AlignedTime: aligned, Type: typ, Size: size, RetryID: retryID, Order: orderCounter}
		orderCounter++

		if existing, exists := records[key]; exists {
			if newRec.RetryID > existing.RetryID {
				records[key] = newRec
			} else if newRec.RetryID == existing.RetryID {
				if newRec.Size > existing.Size {
					records[key] = newRec
				}
			}
		} else {
			records[key] = newRec
		}
	}

	var out []Record
	for _, v := range records {
		out = append(out, v)
	}

	sort.Slice(out, func(i, j int) bool {
		if out[i].AlignedTime != out[j].AlignedTime {
			return out[i].AlignedTime < out[j].AlignedTime
		}
		return out[i].Type < out[j].Type
	})

	for _, r := range out {
		fmt.Printf("%.1f|%s|%d|%d\n", r.AlignedTime, r.Type, r.Size, r.RetryID)
	}
}
EOF

go build -o /app/oracle /app/oracle.go
chmod +x /app/oracle

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
