#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go wget git
    pip3 install pytest

    # Create the vendored package directory
    mkdir -p /app/vendor/github.com/phys-sim/wavegraph

    # Create integrator.go
    cat << 'EOF' > /app/vendor/github.com/phys-sim/wavegraph/integrator.go
package wavegraph

import (
	"math"
)

type GraphSimulation struct {
	nodes int
}

func NewGraphSimulation(nodes int) *GraphSimulation {
	return &GraphSimulation{nodes: nodes}
}

func (g *GraphSimulation) Run(tMax float64) []float64 {
	dt := 1e-6
	maxDt := 0.1
	t := 0.0

	var signal []float64
	sampleInterval := 0.1
	nextSample := 0.0

	for t < tMax {
		if t >= nextSample {
			signal = append(signal, math.Sin(t*2.0*math.Pi + float64(g.nodes)))
			nextSample += sampleInterval
		}
		t += dt
		// dt = math.Min(dt * 1.5, maxDt)
	}

	return signal
}
EOF

    # Create a go.mod for the vendored package
    cat << 'EOF' > /app/vendor/github.com/phys-sim/wavegraph/go.mod
module github.com/phys-sim/wavegraph

go 1.18
EOF

    # Create user and home directory
    useradd -m -s /bin/bash user || true

    # Create baseline.json
    cat << 'EOF' > /home/user/baseline.json
[0.01, 0.02, 0.03, 0.04, 0.05, 0.06, 0.07, 0.08, 0.09, 0.55]
EOF

    # Set up user's go module so they can import the vendored package easily
    cd /home/user
    go mod init analysis
    go mod edit -replace github.com/phys-sim/wavegraph=/app/vendor/github.com/phys-sim/wavegraph

    chmod -R 777 /home/user
    chmod -R 777 /app
