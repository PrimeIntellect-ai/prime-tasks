#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/telemetry
    cd /home/user/telemetry
    go mod init telemetry

    cat << 'EOF' > parser.go
package telemetry

import (
	"math"
	"strconv"
	"strings"
)

type Point struct {
	Lat float32
	Lon float32
	Alt float32
}

func ParseLine(line string) (*Point, error) {
	// Inherited code: ignores errors, panics on missing fields
	parts := strings.Split(line, ",")
	lat, _ := strconv.ParseFloat(parts[1], 32)
	lon, _ := strconv.ParseFloat(parts[2], 32)
	alt, _ := strconv.ParseFloat(parts[3], 32) 
	return &Point{Lat: float32(lat), Lon: float32(lon), Alt: float32(alt)}, nil
}

func Distance(p1, p2 *Point) float64 {
	// Simple euclidean distance
	dx := float64(p1.Lat - p2.Lat)
	dy := float64(p1.Lon - p2.Lon)
	dz := float64(p1.Alt - p2.Alt)
	return math.Sqrt(dx*dx + dy*dy + dz*dz)
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
