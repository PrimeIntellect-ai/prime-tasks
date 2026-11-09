#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang-go
pip3 install pytest

mkdir -p /home/user/simulation

cat << 'EOF' > /home/user/simulation/go.mod
module simulation

go 1.20
EOF

cat << 'EOF' > /home/user/simulation/integrator.go
package main

import "math"

// dy/dt = -0.5 * y^2
func derivative(t, y float64) float64 {
	return -0.5 * y * y
}

func solveODE(t0, y0, tEnd, tol float64) []float64 {
	var result []float64
	t := t0
	y := y0
	dt := 0.01

	for t < tEnd {
		result = append(result, t, y)

		// Heun's method for error estimation
		yEuler := y + dt*derivative(t, y)
		yHeun := y + (dt/2)*(derivative(t, y)+derivative(t+dt, yEuler))

		err := math.Abs(yHeun - yEuler)
		if err == 0 {
			err = 1e-10
		}

		// BUG: Inverted step size adaptation
		dt = dt * (err / tol)

		// Missing clamping in the buggy version (Agent needs to add it)
		// Expected fix:
		// dt = dt * (tol / err)
		// if dt > 0.1 { dt = 0.1 }
		// if dt < 1e-6 { dt = 1e-6 }

		y = yHeun
		t += dt

		// Safety break for the buggy version so it doesn't OOM the test environment immediately
		if len(result) > 200000 {
			break
		}
	}
	return result
}
EOF

cat << 'EOF' > /home/user/simulation/main.go
package main

import (
	"fmt"
)

func main() {
	// Initial conditions
	flatData := solveODE(0.0, 2.0, 10.0, 1e-3)

	// Print length just to do something
	fmt.Printf("Generated %d data points\n", len(flatData))
}
EOF

cat << 'EOF' > /home/user/setup_obs.py
import csv

def exact_solution(t):
    # dy/dt = -0.5 y^2, y(0) = 2 => y(t) = 2 / (t + 1)
    return 2.0 / (t + 1.0)

with open("/home/user/simulation/observational_data.csv", "w") as f:
    writer = csv.writer(f)
    t = 0.0
    # Simulate the adaptive steps roughly
    while t < 10.0:
        writer.writerow([t, exact_solution(t)])
        t += 0.05
EOF
python3 /home/user/setup_obs.py
rm /home/user/setup_obs.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
