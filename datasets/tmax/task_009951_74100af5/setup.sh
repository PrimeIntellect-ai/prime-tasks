#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang gcc libc6-dev
pip3 install pytest

mkdir -p /home/user/numeric-lib

cat << 'EOF' > /home/user/numeric-lib/go.mod
module numeric-lib

go 1.20
EOF

cat << 'EOF' > /home/user/numeric-lib/algo.h
#ifndef ALGO_H
#define ALGO_H

double compute_polynomial(double x);

#endif
EOF

cat << 'EOF' > /home/user/numeric-lib/algo.c
#include "algo.h"

// BUG: Shared state causing race conditions during concurrent property-based testing
static double cache[3];

double compute_polynomial(double x) {
    cache[0] = x;
    cache[1] = x * x;
    cache[2] = x * x * x;

    // Compute 3x^3 + 2x^2 + x
    return (3.0 * cache[2]) + (2.0 * cache[1]) + cache[0];
}
EOF

cat << 'EOF' > /home/user/numeric-lib/num.go
package num

// #cgo CFLAGS: -g -Wall
// #include "algo.h"
import "C"

func ComputePolynomial(x float64) float64 {
	return float64(C.compute_polynomial(C.double(x)))
}
EOF

cat << 'EOF' > /home/user/numeric-lib/num_test.go
package num

import (
	"math"
	"testing"
	"testing/quick"
)

func TestComputePolynomialConcurrent(t *testing.T) {
	t.Parallel()

	property := func(x float64) bool {
		// constrain x to avoid infinity/NaN issues
		if x > 1000 || x < -1000 {
			return true
		}

		got := ComputePolynomial(x)
		expected := (3.0 * x * x * x) + (2.0 * x * x) + x

		// Allow small floating point differences
		return math.Abs(got-expected) < 0.0001
	}

	config := &quick.Config{
		MaxCount: 1000,
	}

	if err := quick.Check(property, config); err != nil {
		t.Error(err)
	}
}

func TestComputePolynomialConcurrent2(t *testing.T) {
	t.Parallel()
	// Duplicate test to force concurrency and trigger the race detector
	property := func(x float64) bool {
		if x > 1000 || x < -1000 { return true }
		got := ComputePolynomial(x)
		expected := (3.0 * x * x * x) + (2.0 * x * x) + x
		return math.Abs(got-expected) < 0.0001
	}
	config := &quick.Config{ MaxCount: 1000 }
	if err := quick.Check(property, config); err != nil {
		t.Error(err)
	}
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
