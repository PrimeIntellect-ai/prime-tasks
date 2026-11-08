#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg golang
    pip3 install pytest

    mkdir -p /app

    # Create the video
    ffmpeg -f lavfi -i testsrc=duration=5:size=320x240:rate=30 -c:v libx264 -pix_fmt yuv420p /app/experiment.mp4

    # Create the oracle Go source
    cat << 'EOF' > /app/oracle_solver.go
package main

import (
	"fmt"
	"math"
	"os"
	"strconv"
)

func main() {
	if len(os.Args) != 4 {
		os.Exit(1)
	}
	cx, _ := strconv.ParseFloat(os.Args[1], 64)
	cy, _ := strconv.ParseFloat(os.Args[2], 64)
	R, _ := strconv.ParseFloat(os.Args[3], 64)

	N := 150 // Ground truth frame count from video
	dx := (2.0 * R) / float64(N)
	dy := (2.0 * R) / float64(N)
	area := dx * dy

	sum := 0.0
	for i := 0; i < N; i++ {
		x := -R + (float64(i)+0.5)*dx
		for j := 0; j < N; j++ {
			y := -R + (float64(j)+0.5)*dy
			denom := math.Sqrt((x-cx)*(x-cx) + (y-cy)*(y-cy) + 1e-8)
			sum += (1.0 / denom) * area
		}
	}
	fmt.Printf("%.6f\n", sum)
}
EOF

    # Compile the oracle
    go build -o /app/oracle_solver /app/oracle_solver.go
    chmod +x /app/oracle_solver

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
