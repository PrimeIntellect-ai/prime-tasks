#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        golang-go \
        imagemagick \
        fonts-dejavu-core

    pip3 install pytest

    mkdir -p /app

    # Generate the image fixture
    # Update ImageMagick policy to allow text/font operations if restricted
    sed -i 's/rights="none" pattern="PDF"/rights="read|write" pattern="PDF"/g' /etc/ImageMagick-6/policy.xml || true

    convert -size 800x200 xc:white -font DejaVu-Sans -pointsize 20 -fill black \
        -annotate +20+40 "SYSTEM CONFIGURATION FOR TECH WRITERS\n=====================================\nTarget Base Directory: /var/www/publish/docs\nSecurity Hash Salt: s4LtY_m4Nif3sT_99" \
        /app/config_spec.png

    # Create the oracle builder
    cat << 'EOF' > /app/oracle.go
package main

import (
	"bufio"
	"crypto/sha256"
	"fmt"
	"os"
	"path"
	"sort"
	"strings"
)

func main() {
	baseDir := "/var/www/publish/docs"
	salt := "s4LtY_m4Nif3sT_99"

	included := make(map[string]bool)

	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		if strings.HasPrefix(line, "+ ") {
			p := strings.TrimSpace(line[2:])
			if !path.IsAbs(p) {
				p = path.Join(baseDir, p)
			}
			p = path.Clean(p)
			included[p] = true
		} else if strings.HasPrefix(line, "- ") {
			p := strings.TrimSpace(line[2:])
			if !path.IsAbs(p) {
				p = path.Join(baseDir, p)
			}
			p = path.Clean(p)
			delete(included, p)
		}
	}

	var paths []string
	for p := range included {
		paths = append(paths, p)
	}
	sort.Strings(paths)

	for _, p := range paths {
		hash := sha256.Sum256([]byte(p + salt))
		fmt.Printf("%x %s\n", hash, p)
	}
}
EOF

    cd /app
    go build -o oracle_builder oracle.go

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
