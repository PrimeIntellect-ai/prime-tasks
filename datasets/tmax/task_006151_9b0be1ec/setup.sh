#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/matrix_solver.go
package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: go run matrix_solver.go <pdb_file>")
		os.Exit(1)
	}

	file, err := os.Open(os.Args[1])
	if err != nil {
		panic(err)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	coords := make(map[string]bool)
	atomCount := 0

	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "ATOM  ") || strings.HasPrefix(line, "HETATM") {
			if len(line) >= 54 {
				coord := line[30:54]
				if coords[coord] {
					panic("near-singular matrix: division by zero (duplicate coordinates found)")
				}
				coords[coord] = true
				atomCount++
			}
		}
	}

	// Simulating the successful matrix factorization output
	fmt.Printf("Matrix factorization successful.\nDomain decomposed into 8x8x8 mesh.\nValid atoms processed: %d\nTrace: %.4f\n", atomCount, float64(atomCount)*3.14159)
}
EOF

cat << 'EOF' > /home/user/protein.pdb
HEADER    EXTRACELLULAR MATRIX                    01-JAN-20   1XYZ
TITLE     TEST STRUCTURE FOR SPATIAL DOMAIN DECOMPOSITION
ATOM      1  N   GLY A   1      12.000  10.500   5.100  1.00  0.00           N
ATOM      2  CA  GLY A   1      12.500  11.500   6.100  1.00  0.00           C
ATOM      3  C   GLY A   1      13.500  12.500   5.100  1.00  0.00           C
ATOM      4  O   GLY A   1      14.500  12.500   4.100  1.00  0.00           O
ATOM      5  N   ALA A   2      12.000  10.500   5.100  1.00  0.00           N  <- duplicate coords
ATOM      6  CA  ALA A   2      15.500  13.500   7.100  1.00  0.00           C
ATOM      7  C   ALA A   2      13.500  12.500   5.100  1.00  0.00           C  <- duplicate coords
END
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
