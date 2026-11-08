#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go ffmpeg
    pip3 install pytest

    mkdir -p /app

    # Generate 150-frame video
    ffmpeg -f lavfi -i testsrc=duration=5:size=320x240:rate=30 -c:v libx264 /app/traffic_cam.mp4

    # Create oracle Go program
    cat << 'EOF' > /app/oracle.go
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
)

type InputRecord struct {
	Id    *string  `json:"id"`
	Value *float64 `json:"value"`
}

type OutputRecord struct {
	Id          string  `json:"id"`
	ScaledValue float64 `json:"scaled_value"`
	Value       float64 `json:"value"`
}

func main() {
	seen := make(map[string]bool)
	scanner := bufio.NewScanner(os.Stdin)
	// buffer size increase if needed, but default is usually fine for simple json lines

	for scanner.Scan() {
		line := scanner.Bytes()
		var rec InputRecord
		err := json.Unmarshal(line, &rec)
		if err != nil || rec.Id == nil {
			fmt.Fprintf(os.Stderr, "invalid record\n")
			continue
		}

		if seen[*rec.Id] {
			continue
		}
		seen[*rec.Id] = true

		var val float64
		if rec.Value != nil {
			val = *rec.Value
		}

		out := OutputRecord{
			Id:          *rec.Id,
			ScaledValue: val * 150.0,
			Value:       val,
		}

		outBytes, _ := json.Marshal(out)
		fmt.Println(string(outBytes))
	}
}
EOF

    cd /app
    go build -o oracle_cleaner oracle.go
    chmod +x oracle_cleaner

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
