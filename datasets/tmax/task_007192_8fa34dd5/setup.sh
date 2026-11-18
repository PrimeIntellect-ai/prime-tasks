#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/graph.edges
0 1
0 2
0 3
0 4
0 5
1 2
3 4
EOF

    cat << 'EOF' > /home/user/simulate.go
package main

import (
	"bufio"
	"fmt"
	"math"
	"os"
	"sort"
	"strconv"
	"strings"
)

func main() {
	// Read graph
	file, err := os.Open("/home/user/graph.edges")
	if err != nil {
		panic(err)
	}
	defer file.Close()

	adj := make(map[int][]int)
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		parts := strings.Fields(scanner.Text())
		if len(parts) == 2 {
			u, _ := strconv.Atoi(parts[0])
			v, _ := strconv.Atoi(parts[1])
			adj[u] = append(adj[u], v)
			adj[v] = append(adj[v], u)
		}
	}

	// Simulation parameters
	K := 2.0
	T := 2.0
	omega := 1.0

	// BUG: Hardcoded large step size causes divergence
	dt := 0.5 
	steps := int(T / dt)

	// Initialize phases
	phases := make(map[int]float64)
	var nodes []int
	for n := range adj {
		nodes = append(nodes, n)
	}
	sort.Ints(nodes)

	for _, n := range nodes {
		phases[n] = float64(n) * 0.1
	}

	// Euler integration
	for s := 0; s < steps; s++ {
		newPhases := make(map[int]float64)
		for _, i := range nodes {
			sum := 0.0
			for _, j := range adj[i] {
				sum += math.Sin(phases[j] - phases[i])
			}
			dtheta := omega + K*sum
			newPhases[i] = phases[i] + dt*dtheta
		}
		phases = newPhases
	}

	// Write output
	out, err := os.Create("/home/user/final_phases.csv")
	if err != nil {
		panic(err)
	}
	defer out.Close()

	for _, n := range nodes {
		fmt.Fprintf(out, "%d,%f\n", n, phases[n])
	}
}
EOF

    chmod -R 777 /home/user
