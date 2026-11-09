#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang tesseract-ocr fonts-liberation
    pip3 install pytest Pillow

    mkdir -p /app

    # Create the image using Python and Pillow
    cat << 'EOF' > /app/make_image.py
from PIL import Image, ImageDraw, ImageFont

img = Image.new('RGB', (600, 300), color='white')
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf", 24)
except IOError:
    font = ImageFont.load_default()

text = 'CONFIG DEFINITION\nMISSING_CHAR: "."\nFILL_MODE: FORWARD\nMAX_FILL: 3\nFALLBACK_CHAR: "*"'
d.text((20,20), text, fill=(0,0,0), font=font)
img.save('/app/sensor_config.png')
EOF
    python3 /app/make_image.py

    # Create the oracle code
    cat << 'EOF' > /app/oracle_process_stream.go
package main

import (
	"bufio"
	"fmt"
	"os"
	"regexp"
	"strings"
)

func main() {
	reader := bufio.NewReader(os.Stdin)
	text, _ := reader.ReadString('\n')
	text = strings.TrimSuffix(text, "\n")
	text = strings.TrimSuffix(text, "\r")

	if len(text) == 0 {
		fmt.Print("INVALID")
		os.Exit(1)
	}

	validRegex := regexp.MustCompile(`^[A-Z\.]+$`)
	if !validRegex.MatchString(text) {
		fmt.Print("INVALID")
		os.Exit(1)
	}

	var result []rune
	var lastChar rune = 0
	fillCount := 0

	for _, c := range text {
		if c == '.' {
			if lastChar != 0 && fillCount < 3 {
				result = append(result, lastChar)
				fillCount++
			} else {
				result = append(result, '*')
			}
		} else {
			result = append(result, c)
			lastChar = c
			fillCount = 0
		}
	}

	fmt.Print(string(result))
	os.Exit(0)
}
EOF

    # Compile the oracle
    cd /app
    go build -o oracle_process_stream oracle_process_stream.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
