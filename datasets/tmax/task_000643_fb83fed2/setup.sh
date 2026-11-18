#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/stats
    cd /home/user/stats

    go mod init stats

    cat << 'EOF' > Makefile
test:
	go test ./...
EOF

    cat << 'EOF' > stats.go
package stats

import (
	"math"
	"os"
)

// DetectAnomalies returns a boolean slice where true indicates an outlier.
func DetectAnomalies(data []float64) []bool {
	if os.Getenv("STATS_ENV") != "test" {
		panic("Environment misconfigured: STATS_ENV must be set to 'test'")
	}
	if len(data) == 0 {
		return nil
	}

	var sum float64
	for _, v := range data {
		sum += v
	}
	mean := sum / float64(len(data))

	var variance float64
	for _, v := range data {
		variance += (v - mean) * (v - mean)
	}
	stddev := math.Sqrt(variance / float64(len(data)))

	// Prevent division by zero if all elements are the same
	if stddev == 0 {
		return make([]bool, len(data))
	}

	threshold := 1.5
	result := make([]bool, len(data))
	for i, x := range data {
		// BUG: Incorrect formula implementation
		z := (x - stddev) / mean

		if math.Abs(z) > threshold {
			result[i] = true
		}
	}
	return result
}
EOF

    cat << 'EOF' > stats_test.go
package stats

import (
	"reflect"
	"testing"
)

func TestDetectAnomalies(t *testing.T) {
	data := []float64{10, 10, 10, 10, 110}
	expected := []bool{false, false, false, false, true}

	result := DetectAnomalies(data)

	if !reflect.DeepEqual(result, expected) {
		t.Fatalf("Expected %v, got %v", expected, result)
	}
}
EOF

    chmod -R 777 /home/user
