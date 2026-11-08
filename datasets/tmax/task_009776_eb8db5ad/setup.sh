#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make golang
    pip3 install pytest

    mkdir -p /home/user/seqgen
    cat << 'EOF' > /home/user/seqgen/seqgen.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    int n = atoi(argv[1]);
    srand(42);
    const char bases[] = "ACGT";
    for (int i = 0; i < n; i++) {
        printf(">primer_%d\n", i);
        for (int j = 0; j < 20; j++) {
            putchar(bases[rand() % 4]);
        }
        putchar('\n');
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/seqgen/Makefile
seqgen: seqgen.c
	gcc -O2 -o seqgen seqgen.c
EOF

    mkdir -p /home/user/analyzer
    cat << 'EOF' > /home/user/analyzer/main.go
package main

import (
	"bufio"
	"fmt"
	"math"
	"os"
)

func SimpsonIntegration(x, y []float64) float64 {
	// TODO: Implement Simpson's 1/3 rule
	return 0.0
}

func slowAlignmentScoring(seq string) float64 {
    score := 0.0
    // Artificial bottleneck
    for i := 0; i < 5000; i++ {
        for j := 0; j < len(seq); j++ {
            if seq[j] == 'G' || seq[j] == 'C' {
                score += math.Sin(float64(i)) * 0.0001
            }
        }
    }
    return score
}

func main() {
	if len(os.Args) != 2 {
		fmt.Println("Usage: analyzer <fasta>")
		os.Exit(1)
	}

    // TODO: Add runtime/pprof CPU profiling here to write to /home/user/cpu.prof

	file, err := os.Open(os.Args[1])
	if err != nil {
		panic(err)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	count := 0
	for scanner.Scan() {
		line := scanner.Text()
		if len(line) > 0 && line[0] != '>' {
			slowAlignmentScoring(line)
			count++
		}
	}

	// Generate a dummy PDF curve to integrate (Standard Normal PDF from -5 to 5)
	n := 1001
	x := make([]float64, n)
	y := make([]float64, n)
	minX, maxX := -5.0, 5.0
	step := (maxX - minX) / float64(n-1)

	for i := 0; i < n; i++ {
		x[i] = minX + float64(i)*step
		y[i] = (1.0 / math.Sqrt(2*math.Pi)) * math.Exp(-0.5*x[i]*x[i])
	}

	integral := SimpsonIntegration(x, y)
	fmt.Printf("Integrated Area: %.6f\n", integral)
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
