#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang ffmpeg
    pip3 install pytest

    mkdir -p /app/data /app/bin /home/user/bin

    # Create dummy video
    ffmpeg -f lavfi -i testsrc=duration=30:size=320x240:rate=1 -c:v libx264 /app/data/traffic_cam.mp4

    # Create weights and biases
    python3 -c "
import random
with open('/app/data/weights.csv', 'w') as f:
    for _ in range(16):
        f.write(','.join(str(random.uniform(-1, 1)) for _ in range(8)) + '\n')
with open('/app/data/biases.csv', 'w') as f:
    f.write(','.join(str(random.uniform(-1, 1)) for _ in range(8)) + '\n')
"

    # Create and compile oracle_infer
    cat << 'EOF' > /tmp/oracle.go
package main

import (
	"encoding/csv"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"math"
	"os"
	"strconv"
)

func main() {
	wf, _ := os.Open("/app/data/weights.csv")
	wr := csv.NewReader(wf)
	wrecs, _ := wr.ReadAll()
	weights := make([][]float64, 16)
	for i := 0; i < 16; i++ {
		weights[i] = make([]float64, 8)
		for j := 0; j < 8; j++ {
			weights[i][j], _ = strconv.ParseFloat(wrecs[i][j], 64)
		}
	}

	bf, _ := os.Open("/app/data/biases.csv")
	br := csv.NewReader(bf)
	brecs, _ := br.ReadAll()
	biases := make([]float64, 8)
	for j := 0; j < 8; j++ {
		biases[j], _ = strconv.ParseFloat(brecs[0][j], 64)
	}

	inBytes, _ := ioutil.ReadAll(os.Stdin)
	var input [][]float64
	json.Unmarshal(inBytes, &input)

	var changes []int
	var prevEmb []float64

	for i, frame := range input {
		emb := make([]float64, 8)
		for j := 0; j < 8; j++ {
			sum := biases[j]
			for k := 0; k < 16; k++ {
				sum += frame[k] * weights[k][j]
			}
			if sum < 0 {
				sum = 0
			}
			emb[j] = sum
		}
		if i > 0 {
			var dot, norm1, norm2 float64
			for j := 0; j < 8; j++ {
				dot += emb[j] * prevEmb[j]
				norm1 += emb[j] * emb[j]
				norm2 += prevEmb[j] * prevEmb[j]
			}
			var sim float64
			if norm1 == 0 || norm2 == 0 {
				sim = 1.0
			} else {
				sim = dot / (math.Sqrt(norm1) * math.Sqrt(norm2))
			}
			if sim < 0.8000 {
				changes = append(changes, i)
			}
		}
		prevEmb = emb
	}
	if changes == nil {
		changes = []int{}
	}
	out, _ := json.Marshal(changes)
	fmt.Println(string(out))
}
EOF
    cd /tmp && go build -o /app/bin/oracle_infer oracle.go
    rm /tmp/oracle.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
