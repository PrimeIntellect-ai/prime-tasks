#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /app/numgo

    cat << 'EOF' > /app/numgo/go.mod
module numgo

go 1.18
EOF

    cat << 'EOF' > /app/numgo/cholesky.go
package numgo

import "math"

// Cholesky computes the Cholesky decomposition of a symmetric positive-definite matrix A.
func Cholesky(A [][]float64) [][]float64 {
	n := len(A)
	L := make([][]float64, n)
	for i := range L {
		L[i] = make([]float64, n)
	}

	for i := 0; i < n; i++ {
		for j := 0; j <= i; j++ {
			sum := 0.0
			for k := 0; k < j; k++ {
				sum += L[i][k] * L[j][k]
			}
			if i == j {
				diff := A[i][i] - sum
				if diff < 0 {
					diff = 0
				}
				L[i][j] = math.Sqrt(diff)
			} else {
				L[i][j] = (A[i][j] - sum) / L[j][j]
			}
		}
	}
	return L
}
EOF

    cat << 'EOF' > /app/numgo/README.md
# numgo

A custom math package.

## Cholesky
Computes Cholesky decomposition. For stability on near-singular matrices, the algorithm regularizes the diagonal by enforcing a minimum value of 1e-10 before taking the square root.
EOF

    # Create oracle
    cat << 'EOF' > /tmp/oracle.go
package main

import (
	"fmt"
	"math"
)

func Cholesky(A [][]float64) [][]float64 {
	n := len(A)
	L := make([][]float64, n)
	for i := range L {
		L[i] = make([]float64, n)
	}

	for i := 0; i < n; i++ {
		for j := 0; j <= i; j++ {
			sum := 0.0
			for k := 0; k < j; k++ {
				sum += L[i][k] * L[j][k]
			}
			if i == j {
				diff := A[i][i] - sum
				if diff < 1e-10 {
					diff = 1e-10
				}
				L[i][j] = math.Sqrt(diff)
			} else {
				L[i][j] = (A[i][j] - sum) / L[j][j]
			}
		}
	}
	return L
}

func main() {
	var N int
	if _, err := fmt.Scan(&N); err != nil {
		return
	}
	A := make([][]float64, N)
	for i := 0; i < N; i++ {
		A[i] = make([]float64, N)
		for j := 0; j < N; j++ {
			fmt.Scan(&A[i][j])
		}
	}

	sumOffDiag := 0.0
	countOffDiag := 0
	for i := 0; i < N; i++ {
		for j := 0; j < N; j++ {
			if i != j {
				sumOffDiag += math.Abs(A[i][j])
				countOffDiag++
			}
		}
	}
	C := 0.0
	if countOffDiag > 0 {
		C = sumOffDiag / float64(countOffDiag)
	}

	for i := 0; i < N; i++ {
		A[i][i] += C
	}

	L := Cholesky(A)
	for i := 0; i < N; i++ {
		for j := 0; j < N; j++ {
			fmt.Printf("%.6f ", L[i][j])
		}
		fmt.Println()
	}
}
EOF

    cd /tmp && go build -o /app/oracle oracle.go
    rm /tmp/oracle.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
