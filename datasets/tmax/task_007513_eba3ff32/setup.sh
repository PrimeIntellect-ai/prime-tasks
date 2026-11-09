#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate.go
package main

import (
	"fmt"
	"math/rand"
	"os"

	"gonum.org/v1/gonum/mat"
)

func main() {
	// Near-singular covariance matrix
	data := []float64{
		1.0, 0.9999999, 0.5,
		0.9999999, 1.0, 0.5,
		0.5, 0.5, 1.0,
	}
	cov := mat.NewSymDense(3, data)

	// TODO: Add a ridge of 1e-4 to the diagonal of cov to make it strictly positive definite

	var chol mat.Cholesky
	ok := chol.Factorize(cov)
	if !ok {
		panic("matrix is not positive definite")
	}

	var L mat.Dense
	chol.LTo(&L)

	src := rand.NewSource(42)
	rnd := rand.New(src)

	sumMC := 0.0
	for j := 0; j < 100000; j++ {
		z := mat.NewVecDense(3, []float64{rnd.NormFloat64(), rnd.NormFloat64(), rnd.NormFloat64()})
		var x mat.VecDense
		x.MulVec(&L, z)
		sumMC += x.AtVec(0) + x.AtVec(1) + x.AtVec(2)
	}

	f, _ := os.Create("/home/user/trace.txt")
	defer f.Close()
	fmt.Fprintf(f, "%.6f\n", sumMC)
}
EOF

    chmod -R 777 /home/user
