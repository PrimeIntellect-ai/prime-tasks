#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        golang-go \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu-core

    pip3 install pytest

    mkdir -p /app

    # Create the model specs image
    convert -size 600x300 xc:white -font DejaVu-Sans -pointsize 18 -fill black -annotate +20+40 "Model Architecture (2-Layer Perceptron)\nInputs: A, B\nHidden Node 1 (H1) = ReLU(0.5 * A - 0.2 * B + 0.1)\nHidden Node 2 (H2) = ReLU(0.1 * A + 0.8 * B - 0.1)\nFinal Score = 1.0 * H1 - 1.0 * H2 + 0.5\nNote: ReLU(x) = max(0, x)" /app/model_specs.png

    # Create the oracle scorer in Go
    cat << 'EOF' > /tmp/oracle.go
package main

import (
	"bufio"
	"fmt"
	"math"
	"os"
)

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		var a, b float64
		n, _ := fmt.Sscanf(scanner.Text(), "%f %f", &a, &b)
		if n == 2 {
			h1 := math.Max(0, 0.5*a - 0.2*b + 0.1)
			h2 := math.Max(0, 0.1*a + 0.8*b - 0.1)
			score := 1.0*h1 - 1.0*h2 + 0.5
			fmt.Printf("%.4f\n", score)
		}
	}
}
EOF
    go build -o /app/oracle_scorer /tmp/oracle.go
    chmod +x /app/oracle_scorer

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
