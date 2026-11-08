#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/seq_analyzer /home/user/data

    cat << 'EOF' > /home/user/data/sequences.txt
ATGCATGC
GCGCGCGC
ATATATAT
ATGC
EOF

    cat << 'EOF' > /home/user/data/targets.txt
2.0
0.0
4.0
2.0
EOF

    cat << 'EOF' > /home/user/seq_analyzer/go.mod
module seq_analyzer

go 1.20
EOF

    cat << 'EOF' > /home/user/seq_analyzer/main.go
package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

func computeRatio(seq string) float64 {
	at := 0
	gc := 0
	for _, c := range seq {
		if c == 'A' || c == 'T' {
			at++
		} else if c == 'G' || c == 'C' {
			gc++
		}
	}
	if gc == 0 {
		return float64(at)
	}
	return float64(at) / float64(gc)
}

func main() {
	seqFile, err := os.Open("/home/user/data/sequences.txt")
	if err != nil {
		panic(err)
	}
	defer seqFile.Close()

	targetFile, err := os.Open("/home/user/data/targets.txt")
	if err != nil {
		panic(err)
	}
	defer targetFile.Close()

	var ratios []float64
	seqScanner := bufio.NewScanner(seqFile)
	for seqScanner.Scan() {
		seq := strings.TrimSpace(seqScanner.Text())
		if seq != "" {
			ratios = append(ratios, computeRatio(seq))
		}
	}

	var targets []float64
	targetScanner := bufio.NewScanner(targetFile)
	for targetScanner.Scan() {
		var t float64
		fmt.Sscanf(targetScanner.Text(), "%f", &t)
		targets = append(targets, t)
	}

	k := GradientDescent(ratios, targets, 0.05, 1000)
	fmt.Printf("%.4f\n", k)
}
EOF

    cat << 'EOF' > /home/user/seq_analyzer/optimize.go
package main

func GradientDescent(ratios []float64, targets []float64, lr float64, epochs int) float64 {
	k := 0.0
	for i := 0; i < epochs; i++ {
		grad := 0.0
		for j := 0; j < len(ratios); j++ {
			// BUG: Incorrect gradient calculation
			grad += ratios[j] * (k*ratios[j] + targets[j])
		}
		k -= lr * grad
	}
	return k
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
