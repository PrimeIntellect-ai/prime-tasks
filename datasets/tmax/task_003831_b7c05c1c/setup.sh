#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gnuplot
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/integrator.go
package main

import (
	"encoding/csv"
	"fmt"
	"math"
	"os"
)

func main() {
	// dy/dt = -15 * y
	f := func(t, y float64) float64 {
		return -15.0 * y
	}

	t := 0.0
	y := 1.0
	tEnd := 2.0
	dt := 0.1
	tol := 1e-4

	file, err := os.Create("/home/user/dataset.csv")
	if err != nil {
		panic(err)
	}
	defer file.Close()
	writer := csv.NewWriter(file)
	defer writer.Flush()

	writer.Write([]string{"t", "y"})
	writer.Write([]string{fmt.Sprintf("%f", t), fmt.Sprintf("%f", y)})

	for t < tEnd {
		if t+dt > tEnd {
			dt = tEnd - t
		}

		// Heun's method (RK2) for step
		k1 := f(t, y)
		k2 := f(t+dt, y+dt*k1)
		y1 := y + dt*0.5*(k1+k2)

		// Euler method for error estimation
		y2 := y + dt*k1

		// Local truncation error estimate
		errEst := math.Abs(y1 - y2)

		if errEst == 0 {
			errEst = 1e-10
		}

		if errEst <= tol {
			t += dt
			y = y1
			writer.Write([]string{fmt.Sprintf("%f", t), fmt.Sprintf("%f", y)})
		}

		// Bug: Incorrect step size adaptation. Should be dt * math.Sqrt(tol/errEst)
		// Agent needs to fix this line:
		dt = dt * math.Sqrt(errEst/tol)

        // Safety bounds
		if dt > 0.5 {
			dt = 0.5
		}
		if dt < 1e-5 {
			fmt.Println("Step size too small, diverging!")
			break
		}
	}
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
