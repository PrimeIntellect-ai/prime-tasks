#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        golang-go \
        openssh-client \
        openssh-server \
        tesseract-ocr \
        libtesseract-dev

    pip3 install pytest pillow pytesseract

    mkdir -p /app
    touch /app/base.qcow2

    # Create reference Go program
    cat << 'EOF' > /app/ref.go
package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		line := scanner.Text()
		fmt.Println(strings.ReplaceAll(line, "DEV", "vm-alpha-88"))
	}
}
EOF
    go build -o /app/reference_proxy_filter /app/ref.go
    rm /app/ref.go

    # Create image
    cat << 'EOF' > /app/make_img.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,50), "PORT: 9922\nINSTANCE: vm-alpha-88", fill=(0,0,0))
img.save('/app/vm_config.png')
EOF
    python3 /app/make_img.py
    rm /app/make_img.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
