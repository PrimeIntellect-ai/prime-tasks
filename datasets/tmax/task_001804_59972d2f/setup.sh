#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gawk
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/initial_states.csv
10.5
22.1
5.4
100.0
50.2
12.3
8.8
EOF

    cat << 'EOF' > /home/user/simulate.go
package main

import (
	"bufio"
	"fmt"
	"log"
	"os"
	"strconv"
)

func main() {
	file, err := os.Open("/home/user/initial_states.csv")
	if err != nil {
		log.Fatal(err)
	}
	defer file.Close()

	outFile, err := os.Create("/home/user/final_states.txt")
	if err != nil {
		log.Fatal(err)
	}
	defer outFile.Close()

	scanner := bufio.NewScanner(file)
	k := 0.5
	t_end := 5.0
	// BUG: dt is too large
	dt := 2.5

	for scanner.Scan() {
		y0, err := strconv.ParseFloat(scanner.Text(), 64)
		if err != nil {
			continue
		}

		y := y0
		for t := 0.0; t < t_end; t += dt {
			// Euler method step
			dy := -k * y
			y += dy * dt
		}

		fmt.Fprintf(outFile, "%f\n", y)
	}
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
