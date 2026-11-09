#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang git
    pip3 install pytest

    mkdir -p /home/user/math-solver
    cd /home/user/math-solver

    git init
    git config user.email "test@example.com"
    git config user.name "Test User"

    # Commit 1 (Good)
    cat << 'EOF' > solver.go
package solver

import "math"

func FindRoot(guess float64, epsilon float64) float64 {
	x := guess
	for i := 0; i < 1000; i++ {
		fx := x*x*x - 2*x - 5
		dfx := 3*x*x - 2
		step := fx / dfx
		xNext := x - step
		if math.Abs(xNext - x) < epsilon {
			return xNext
		}
		x = xNext
	}
	return math.NaN()
}
EOF

    cat << 'EOF' > go.mod
module math-solver

go 1.18
EOF

    cat << 'EOF' > solver_test.go
package solver

import (
	"math"
	"testing"
)

func TestFindRoot(t *testing.T) {
	root := FindRoot(2.0, 1e-9)
	if math.IsNaN(root) {
		t.Fatalf("FindRoot failed to converge")
	}
	expected := 2.09455148
	if math.Abs(root-expected) > 1e-7 {
		t.Fatalf("Expected %v, got %v", expected, root)
	}
}
EOF

    git add .
    git commit -m "Initial commit"
    git tag v1.0

    # Commit 2
    cat << 'EOF' >> solver.go

func Add(a, b float64) float64 {
	return a + b
}
EOF
    git add solver.go
    git commit -m "Add simple addition"

    # Commit 3 (Buggy)
    cat << 'EOF' > solver.go
package solver

import "math"

func FindRoot(guess float64, epsilon float64) float64 {
	x := guess
	for i := 0; i < 1000; i++ {
		// Memory optimization
		x32 := float32(x)
		fx := x32*x32*x32 - 2*x32 - 5
		dfx := 3*x32*x32 - 2
		step := float64(fx / dfx)

		xNext := x - step
		if math.Abs(xNext - x) < epsilon {
			return xNext
		}
		x = xNext
	}
	return math.NaN()
}

func Add(a, b float64) float64 {
	return a + b
}
EOF
    git add solver.go
    git commit -m "Optimize memory usage by using float32 for intermediate step"
    BUGGY_COMMIT=$(git rev-parse HEAD)

    # Commit 4
    cat << 'EOF' >> solver_test.go

func TestAdd(t *testing.T) {
	if Add(1.0, 2.0) != 3.0 {
		t.Fatalf("Add failed")
	}
}

func TestAddZero(t *testing.T) {
	if Add(0.0, 0.0) != 0.0 {
		t.Fatalf("Add zero failed")
	}
}
EOF
    git add solver_test.go
    git commit -m "Add tests for addition"

    # Commit 5
    echo "# Math Solver" > README.md
    git add README.md
    git commit -m "Add README"

    echo "$BUGGY_COMMIT" > /home/user/.buggy_commit

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
