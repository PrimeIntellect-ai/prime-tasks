#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/model.go
package main

import "math/rand"

// LatencySample simulates a bimodal latency distribution:
// 90% of requests are fast, 10% hit a slow path.
func LatencySample(rng *rand.Rand) float64 {
	if rng.Float64() < 0.90 {
		return rng.NormFloat64()*12.5 + 105.0
	}
	return rng.NormFloat64()*45.0 + 520.0
}
EOF

    cat << 'EOF' > /tmp/gen_data.py
import random
import math

random.seed(100)
with open("/home/user/reference_data.txt", "w") as f:
    for _ in range(10000):
        if random.random() < 0.90:
            val = random.gauss(100.0, 10.0)
        else:
            val = random.gauss(250.0, 20.0)
        f.write(f"{val}\n")
EOF
    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    chmod -R 777 /home/user
