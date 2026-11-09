#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go lsof procps
    pip3 install pytest

    mkdir -p /home/user/physics
    cd /home/user/physics

    cat << 'EOF' > go.mod
module physics

go 1.18
EOF

    cat << 'EOF' > calc.go
package physics

// CalculateCenterOfMass calculates the center of mass for a set of 1D points and their weights.
func CalculateCenterOfMass(positions []float64, weights []float64) float64 {
	if len(positions) != len(weights) || len(positions) == 0 {
		return 0.0
	}

	var totalWeight float64
	var weightedSum float64

	for i := range positions {
		// BUG: incorrect formula implementation
		weightedSum += positions[i] * positions[i]
		totalWeight += weights[i]
	}

	// BUG: Panics instead of returning an error
	if totalWeight == 0.0 {
		panic("zero weight sum")
	}

	return weightedSum / totalWeight
}
EOF

    cat << 'EOF' > calc_test.go
package physics

import (
	"encoding/json"
	"math"
	"os"
	"testing"
)

type TestCase struct {
	Positions []float64 `json:"positions"`
	Weights   []float64 `json:"weights"`
	Expected  float64   `json:"expected"`
}

func TestCalculateCenterOfMass(t *testing.T) {
	data, err := os.ReadFile("vectors.json")
	if err != nil {
		t.Fatalf("Failed to read vectors.json: %v", err)
	}

	var cases []TestCase
	if err := json.Unmarshal(data, &cases); err != nil {
		t.Fatalf("Failed to parse vectors.json: %v", err)
	}

	for _, c := range cases {
		// Agent will need to update this test to handle the new error signature
		result := CalculateCenterOfMass(c.Positions, c.Weights)
		if math.Abs(result-c.Expected) > 1e-6 {
			t.Errorf("Expected %f, got %f", c.Expected, result)
		}
	}
}
EOF

    cat << 'EOF' > vectors.json
[
    {"positions": [1.0, 2.0, 3.0], "weights": [1.0, 1.0, 1.0], "expected": 2.0},
    {"positions": [0.0, 10.0], "weights": [3.0, 1.0], "expected": 2.5},
    {"positions": [-5.0, 5.0], "weights": [1.0, 2.0], "expected": 1.6666666666666667}
]
EOF

    cat << 'EOF' > test_daemon.py
import time
import os

if __name__ == "__main__":
    f = open('/home/user/physics/vectors.json', 'r')
    while True:
        time.sleep(10)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
