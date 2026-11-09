#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go imagemagick tesseract-ocr
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Create the image using ImageMagick
    # Need to install fonts for ImageMagick
    apt-get install -y fonts-dejavu-core
    convert -size 400x200 xc:white -font DejaVu-Sans-Mono -pointsize 24 -fill black \
      -draw "text 20,50 'CHARSET=ISO-8859-1'" \
      -draw "text 20,90 'RECORD_SIZE=32'" \
      -draw "text 20,130 'THRESHOLD=50'" \
      /app/data_spec.png

    # Create the Oracle program
    cat << 'EOF' > /app/oracle.go
package main

import (
	"fmt"
	"io"
	"math"
	"os"
	"strconv"
	"strings"
	"golang.org/x/text/encoding/charmap"
)

func main() {
	decoder := charmap.ISO8859_1.NewDecoder()
	seen := make(map[string]bool)
	var lastVal *int

	buf := make([]byte, 32)
	for {
		n, err := io.ReadFull(os.Stdin, buf)
		if err != nil {
			break // EOF or unexpected EOF (ignore partial)
		}
		if n != 32 {
			break
		}

		decodedBytes, _ := decoder.Bytes(buf)
		decoded := string(decodedBytes)

		if len(decoded) < 16 {
			continue
		}

		id := decoded[0:8]
		valStr := strings.TrimSpace(decoded[8:16])
		val, err := strconv.Atoi(valStr)
		if err != nil {
			continue // skip invalid parse
		}

		if seen[id] {
			continue
		}
		seen[id] = true

		if lastVal != nil {
			if math.Abs(float64(val-*lastVal)) > 50 {
				fmt.Printf("ANOMALY DETECTED AT ID:%s\n", id)
				os.Exit(0)
			}
		}

		lastVal = &val
		fmt.Printf("[%s] -> %d\n", id, val)
	}
}
EOF

    cd /app
    go mod init oracle
    go get golang.org/x/text/encoding/charmap
    go build -o oracle_processor oracle.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
