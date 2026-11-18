#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr golang fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app
    convert -size 800x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
    -draw "text 20,60 'Window Function: W(n) = 0.53836 - 0.46164 * cos(2 * pi * n / (N - 1))'" \
    -draw "text 20,120 'Summation Method: Kahan Summation Algorithm'" \
    /app/window_spec.png

    cat << 'EOF' > /app/oracle_dft_tool.go
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
	scanner := bufio.NewScanner(os.Stdin)
	var zVals []float64

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		parts := strings.Fields(line)
		if len(parts) == 5 && parts[0] == "ATOM" {
			_, err1 := strconv.Atoi(parts[1])
			_, err2 := strconv.ParseFloat(parts[2], 64)
			_, err3 := strconv.ParseFloat(parts[3], 64)
			z, err4 := strconv.ParseFloat(parts[4], 64)
			if err1 == nil && err2 == nil && err3 == nil && err4 == nil {
				zVals = append(zVals, z)
			}
		}
	}

	N := len(zVals)
	if N == 0 {
		fmt.Printf("%.6f\n", 0.0)
		return
	}

	windowed := make([]float64, N)
	for n := 0; n < N; n++ {
		w := 1.0
		if N > 1 {
			w = 0.53836 - 0.46164*math.Cos(2.0*math.Pi*float64(n)/float64(N-1))
		}
		windowed[n] = zVals[n] * w
	}

	magSq := make([]float64, N)
	for k := 0; k < N; k++ {
		re, im := 0.0, 0.0
		for n := 0; n < N; n++ {
			angle := -2.0 * math.Pi * float64(k*n) / float64(N)
			re += windowed[n] * math.Cos(angle)
			im += windowed[n] * math.Sin(angle)
		}
		magSq[k] = re*re + im*im
	}

	sum := 0.0
	c := 0.0
	for _, val := range magSq {
		y := val - c
		t := sum + y
		c = (t - sum) - y
		sum = t
	}

	fmt.Printf("%.6f\n", sum)
}
EOF

    cd /app
    go build -o /app/oracle_dft_tool /app/oracle_dft_tool.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
