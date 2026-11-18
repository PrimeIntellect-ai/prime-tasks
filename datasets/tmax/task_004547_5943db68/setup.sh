#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go tesseract-ocr imagemagick
    pip3 install pytest

    mkdir -p /app

    # Generate the rule image
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
        -draw "text 10,50 'EXTENSION: .zz'" \
        -draw "text 10,100 'KEYWORD: ERROR'" \
        /app/rule.png

    # Create the oracle
    cat << 'EOF' > /app/oracle.go
package main

import (
	"bufio"
	"compress/gzip"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func main() {
	if len(os.Args) != 2 {
		return
	}
	dir := os.Args[1]
	count := 0

	filepath.Walk(dir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		if !info.IsDir() && strings.HasSuffix(path, ".zz") {
			f, err := os.Open(path)
			if err != nil {
				return nil
			}
			defer f.Close()

			gz, err := gzip.NewReader(f)
			if err != nil {
				return nil
			}
			defer gz.Close()

			scanner := bufio.NewScanner(gz)
			for scanner.Scan() {
				if strings.Contains(scanner.Text(), "ERROR") {
					count++
				}
			}
		}
		return nil
	})

	fmt.Println(count)
}
EOF

    go build -o /app/oracle_archive_scanner /app/oracle.go
    rm /app/oracle.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
