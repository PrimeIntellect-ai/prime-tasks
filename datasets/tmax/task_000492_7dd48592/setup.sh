#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/cluster_sim.go
package main

import (
	"fmt"
	"math/rand"
)

func main() {
	rand.Seed(42)
	// We generate 2,500,000 pairs (5,000,000 total)
	for i := 0; i < 2500000; i++ {
		baseX := 1e12 + rand.Float64()*1000
		baseY := 1e12 + rand.Float64()*1000
		baseZ := 1e12 + rand.Float64()*1000

		// Pair 1
		fmt.Printf("%.6f,%.6f,%.6f,1.0\n", baseX, baseY, baseZ)
		// Pair 2
		fmt.Printf("%.6f,%.6f,%.6f,1.0\n", -baseX + 1e-4, -baseY + 1e-4, -baseZ + 1e-4)
	}
}
EOF
    go build -ldflags="-s -w" -o /app/cluster_sim /tmp/cluster_sim.go
    chmod +x /app/cluster_sim
    rm /tmp/cluster_sim.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
