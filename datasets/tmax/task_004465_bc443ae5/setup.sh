#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr golang-go fonts-liberation
    pip3 install pytest pillow

    mkdir -p /app
    mkdir -p /opt/oracle

    # Generate the image
    cat << 'EOF' > /tmp/gen_img.py
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 32)
except:
    font = ImageFont.load_default()
text = "0.45 0.10 -0.85\n-0.20 0.75 0.50"
d.text((10, 10), text, fill=(0, 0, 0), font=font)
img.save('/app/projection_matrix.png')
EOF
    python3 /tmp/gen_img.py

    # Create and compile the oracle
    cat << 'EOF' > /tmp/reference_reducer.go
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
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		parts := strings.Split(line, ",")
		if len(parts) != 3 {
			continue
		}
		x1, _ := strconv.ParseFloat(strings.TrimSpace(parts[0]), 64)
		x2, _ := strconv.ParseFloat(strings.TrimSpace(parts[1]), 64)
		x3, _ := strconv.ParseFloat(strings.TrimSpace(parts[2]), 64)

		y1 := 0.45*x1 + 0.10*x2 - 0.85*x3
		y2 := -0.20*x1 + 0.75*x2 + 0.50*x3

		fmt.Printf("%.4f,%.4f\n", y1, y2)
	}
}
EOF
    go build -o /opt/oracle/reference_reducer /tmp/reference_reducer.go
    chmod +x /opt/oracle/reference_reducer

    # Clean up
    rm /tmp/gen_img.py /tmp/reference_reducer.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
