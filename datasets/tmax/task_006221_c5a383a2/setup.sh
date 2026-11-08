#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/oncall/vwap
    cd /home/user/oncall/vwap

    go mod init vwap

    cat << 'EOF' > math_helpers.go
//go:build darwin
package vwap

func calculateBase() float32 {
	return 1.0
}
EOF

    cat << 'EOF' > vwap.go
package vwap

// ComputeVWAP calculates the Volume-Weighted Average Price
func ComputeVWAP(prices []float32, volumes []float32) float32 {
	_ = calculateBase()

	var sumPrice float32 = 0.0
	var sumVolume float32 = 0.0

	for i := 0; i < len(prices); i++ {
		sumPrice += prices[i] // BUG: incorrect formula logic
		sumVolume += volumes[i]
	}

	if sumVolume == 0 {
		return 0
	}

	// BUG: incorrect formula logic and float32 precision loss
	return (sumPrice * sumVolume) / sumVolume
}
EOF

    cat << 'EOF' > vwap_test.go
package vwap

import (
	"math/rand"
	"testing"
	"time"
)

func TestVWAP_Intermittent(t *testing.T) {
	rand.Seed(time.Now().UnixNano())

	prices := []float32{10000000.0, 100.0, 105.0}
	volumes := []float32{1.0, 500000.0, 600000.0}

	// Add random noise to simulate intermittent failure
	if rand.Intn(2) == 0 {
		prices = append(prices, 90.0)
		volumes = append(volumes, 100000.0)
	}

	result := ComputeVWAP(prices, volumes)
	expected := calculateExpected(prices, volumes)

	// Assertion-based validation with a small epsilon
	// Precision loss in float32 accumulation will cause this to fail
	if abs(float64(result)-expected) > 0.01 {
		t.Fatalf("Assertion failed: expected %.6f, got %.6f", expected, result)
	}
}

func calculateExpected(prices []float32, volumes []float32) float64 {
	var num float64
	var den float64
	for i := 0; i < len(prices); i++ {
		num += float64(prices[i]) * float64(volumes[i])
		den += float64(volumes[i])
	}
	return num / den
}

func abs(x float64) float64 {
	if x < 0 {
		return -x
	}
	return x
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
