#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang tesseract-ocr
    pip3 install pytest pillow

    mkdir -p /app

    # Create the oracle Go code
    cat << 'EOF' > /app/oracle.go
package main

import (
	"bufio"
	"encoding/base64"
	"fmt"
	"os"
	"strings"
)

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	if !scanner.Scan() {
		return
	}
	input := scanner.Text()

	decoded, err := base64.StdEncoding.DecodeString(input)
	if err != nil {
		fmt.Print("ERR_DECODE")
		return
	}

	payload := string(decoded)

	if strings.Contains(payload, "ssh-rsa") && strings.Contains(payload, "root") {
		fmt.Print("SILENT_REJECT")
		return
	}

	if strings.HasPrefix(payload, "GET /api") {
		fmt.Print("LB_API")
		return
	}

	if strings.Contains(payload, "admin") && len(payload) > 20 {
		fmt.Print("LB_ADMIN")
		return
	}

	fmt.Print("DEFAULT_ROUTE")
}
EOF

    # Compile the oracle
    cd /app
    go build -o proxy_oracle oracle.go
    chmod +x proxy_oracle
    rm oracle.go

    # Generate the image
    cat << 'EOF' > /app/gen_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 300), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = """ROUTING POLICY V2:
1. If payload cannot be base64 decoded, output "ERR_DECODE".
2. If payload contains both "ssh-rsa" and "root", output "SILENT_REJECT".
3. If payload starts with "GET /api", output "LB_API".
4. If payload contains "admin" and length of decoded payload > 20, output "LB_ADMIN".
5. Otherwise, output "DEFAULT_ROUTE".
Note: Rule 1 takes highest precedence, then 2, 3, 4, 5."""
d.text((10,10), text, fill=(0,0,0))
img.save('/app/proxy_rules.png')
EOF

    python3 /app/gen_image.py
    rm /app/gen_image.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
