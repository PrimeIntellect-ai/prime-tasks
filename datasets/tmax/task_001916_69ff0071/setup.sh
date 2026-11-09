#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

# Install task-specific dependencies
apt-get install -y golang imagemagick tesseract-ocr fonts-dejavu-core

# Create /app directory
mkdir -p /app
cd /app

# Generate the image fixture using imagemagick
convert -size 300x50 xc:white -font DejaVu-Sans -pointsize 18 -fill black -draw "text 10,30 'w1=1.5, w2=2.0, w3=-0.5, w4=0.8'" /app/weights.png

# Create the oracle
cat << 'EOF' > /app/oracle.go
package main

import (
	"bufio"
	"fmt"
	"math"
	"os"
	"strconv"
	"strings"
)

func main() {
	weights := []float64{1.5, 2.0, -0.5, 0.8}
	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" { continue }
		parts := strings.Split(line, ",")
		var vals []float64
		for _, p := range parts {
			v, _ := strconv.ParseFloat(strings.TrimSpace(p), 64)
			vals = append(vals, v)
		}
		if len(vals) != 4 { continue }

		maxVal := math.Inf(-1)
		for i := range vals {
			vals[i] = vals[i] * weights[i]
			if vals[i] > maxVal {
				maxVal = vals[i]
			}
		}

		sumExp := 0.0
		for i := range vals {
			sumExp += math.Exp(vals[i] - maxVal)
		}

		result := maxVal + math.Log(sumExp)
		fmt.Printf("%.6f\n", result)
	}
}
EOF

go build -o /app/oracle /app/oracle.go
rm /app/oracle.go

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
