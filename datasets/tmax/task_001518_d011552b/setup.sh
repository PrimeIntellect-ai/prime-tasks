#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang-go
pip3 install pytest

mkdir -p /app/data /home/user/cleaner
cd /app

# Create the embedder in Go
cat << 'EOF' > embedder.go
package main

import (
	"fmt"
	"hash/crc32"
	"math/rand"
	"os"
	"strings"
)

func main() {
	if len(os.Args) < 2 {
		return
	}
	text := os.Args[1]
	checksum := crc32.ChecksumIEEE([]byte(text))
	rng := rand.New(rand.NewSource(int64(checksum)))

	vals := make([]string, 16)
	for i := 0; i < 16; i++ {
		// Scale down to ensure distances to 5th NN are mostly <= 2.5
		vals[i] = fmt.Sprintf("%.6f", rng.NormFloat64()*0.2)
	}
	fmt.Println(strings.Join(vals, ","))
}
EOF
go build -ldflags="-s -w" -o embedder embedder.go
rm embedder.go

# Create dataset.csv
cat << 'EOF' > generate_data.py
import random
import csv

random.seed(42)
with open('dataset.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'text'])
    for i in range(500):
        writer.writerow([str(i), f"text_record_{i}_{random.randint(0, 1000000)}"])
EOF
python3 generate_data.py
rm generate_data.py

# Compute ground truth centroid
cat << 'EOF' > compute_truth.py
import subprocess
import csv
import math

records = []
with open('dataset.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        text = row['text']
        out = subprocess.check_output(['./embedder', text]).decode('utf-8').strip()
        vec = [float(x) for x in out.split(',')]
        records.append(vec)

def dist(v1, v2):
    return math.sqrt(sum((a - b)**2 for a, b in zip(v1, v2)))

clean_records = []
for i, r1 in enumerate(records):
    distances = []
    for j, r2 in enumerate(records):
        distances.append(dist(r1, r2))
    distances.sort()
    # 1st nearest is itself (distance 0)
    # 5th nearest neighbor is at index 4
    if distances[4] <= 2.5:
        clean_records.append(r1)

if len(clean_records) == 0:
    raise ValueError("No clean records found. Threshold is too strict or embeddings too spread out.")

centroid = []
for k in range(16):
    centroid.append(sum(r[k] for r in clean_records) / len(clean_records))

with open('truth_centroid.txt', 'w') as f:
    f.write(','.join(f"{x:.6f}" for x in centroid))
EOF
python3 compute_truth.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
