#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest Pillow

    mkdir -p /app

    # Create the secret image using Pillow
    cat << 'EOF' > /app/make_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 50), "SECRET_KEY: KRAKEN99", fill=(0, 0, 0))
img.save('/app/restore_secret.png')
EOF
    python3 /app/make_image.py
    rm /app/make_image.py

    # Create and compile the oracle
    cat << 'EOF' > /app/oracle_validator.go
package main

import (
	"crypto/md5"
	"encoding/hex"
	"fmt"
	"os"
	"path"
	"strings"
)

func main() {
	if len(os.Args) != 2 {
		return
	}
	p := path.Clean(os.Args[1])
	secret := "KRAKEN99"

	if strings.Contains(p, secret) {
		fmt.Println("ACL: 0777")
		return
	}

	if p == "/restricted" || strings.HasPrefix(p, "/restricted/") {
		fmt.Println("ACL: 0600")
		return
	}

	hasher := md5.New()
	hasher.Write([]byte(p))
	hashHex := hex.EncodeToString(hasher.Sum(nil))
	fmt.Printf("ACL: 0644 HASH: %s\n", hashHex[:4])
}
EOF
    go build -o /app/oracle_validator /app/oracle_validator.go
    rm /app/oracle_validator.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
