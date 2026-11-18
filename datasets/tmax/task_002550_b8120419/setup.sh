#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go imagemagick
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /app/oracle.go
package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	buf := make([]byte, 1024*1024)
	scanner.Buffer(buf, 1024*1024)
	if !scanner.Scan() {
		return
	}
	parts := strings.Fields(scanner.Text())
	n := len(parts)
	if n == 0 {
		return
	}

	x := make([]float64, n)
	for i, p := range parts {
		val, _ := strconv.ParseFloat(p, 64)
		x[i] = val
	}

	y := make([]float64, n)
	for i := 0; i < n; i++ {
		var val float64
		if i-2 >= 0 { val += 0.1 * x[i-2] }
		if i-1 >= 0 { val += 0.2 * x[i-1] }
		val += 0.4 * x[i]
		if i+1 < n { val += 0.2 * x[i+1] }
		if i+2 < n { val += 0.1 * x[i+2] }
		y[i] = val
	}

	var E float64 = 0.0
	for i := 0; i < n; i++ {
		E += y[i] * y[i]
	}

	fmt.Printf("%.8f\n", E)
}
EOF

    cd /app
    go build -o oracle_processor oracle.go
    chmod +x oracle_processor

    convert -background white -fill black -pointsize 24 label:"SMOOTHING COEFFICIENTS\nC_{-2} = 0.1\nC_{-1} = 0.2\nC_{0} = 0.4\nC_{1} = 0.2\nC_{2} = 0.1\n\nFor boundaries, treat out-of-bounds inputs as 0.0.\nCalculate Spectral Energy: E = Sum_{i=0}^{N-1} (y_i * y_i)" /app/filter_spec.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
