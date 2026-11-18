#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr build-essential golang-go imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app/c_scanner
    mkdir -p /app/go_waf/internal/config
    mkdir -p /app/go_waf/internal/scanner
    mkdir -p /app/go_waf/internal/versions
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Generate the image
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,50 'BLOCK SEMVER RANGE:' text 10,80 '< 1.4.0' text 10,110 '>= 2.0.0-alpha'" /app/version_rules.png

    # Create C scanner files
    cat << 'EOF' > /app/c_scanner/Makefile
libscanner.so: scanner.c
	gcc -o libscanner.so scanner.c
EOF

    cat << 'EOF' > /app/c_scanner/scanner.c
#include <string.h>
int scan_payload(const char* payload) {
    if (strstr(payload, "DROP TABLE") != NULL) return 1;
    if (strstr(payload, "<script>") != NULL) return 1;
    return 0;
}
EOF

    cat << 'EOF' > /app/c_scanner/scanner.h
int scan_payload(const char* payload);
EOF

    # Create Go files
    cat << 'EOF' > /app/go_waf/go.mod
module waf

go 1.18
EOF

    cat << 'EOF' > /app/go_waf/main.go
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"
	"waf/internal/scanner"
	"waf/internal/versions"
)

type Request struct {
	Version string `json:"version"`
	Payload string `json:"payload"`
}

func main() {
	dirPtr := flag.String("dir", "", "target directory")
	outPtr := flag.String("out", "", "output file")
	flag.Parse()

	if *dirPtr == "" || *outPtr == "" {
		fmt.Println("Usage: -dir <dir> -out <file>")
		os.Exit(1)
	}

	files, err := ioutil.ReadDir(*dirPtr)
	if err != nil {
		panic(err)
	}

	results := make(map[string]string)
	for _, f := range files {
		if filepath.Ext(f.Name()) == ".json" {
			data, err := ioutil.ReadFile(filepath.Join(*dirPtr, f.Name()))
			if err != nil {
				continue
			}
			var req Request
			json.Unmarshal(data, &req)

			isEvil := false
			if !versions.IsAllowed(req.Version) {
				isEvil = true
			} else if scanner.Scan(req.Payload) {
				isEvil = true
			}

			if isEvil {
				results[f.Name()] = "EVIL"
			} else {
				results[f.Name()] = "CLEAN"
			}
		}
	}

	outData, _ := json.MarshalIndent(results, "", "  ")
	ioutil.WriteFile(*outPtr, outData, 0644)
}
EOF

    cat << 'EOF' > /app/go_waf/internal/config/config.go
package config

import "waf/internal/scanner"

type Config struct {
	MaxPayloadSize int
}

func GetDefaultConfig() Config {
	_ = scanner.GetDefaultScanner()
	return Config{MaxPayloadSize: 1024}
}
EOF

    cat << 'EOF' > /app/go_waf/internal/scanner/scanner.go
package scanner

/*
#cgo LDFLAGS: -L../../../c_scanner -lscanner
#include "../../../c_scanner/scanner.h"
*/
import "C"
import "waf/internal/config"

type Scanner struct{}

func GetDefaultScanner() Scanner {
	_ = config.Config{}
	return Scanner{}
}

func Scan(payload string) bool {
	cStr := C.CString(payload)
	res := C.scan_payload(cStr)
	return res == 1
}
EOF

    cat << 'EOF' > /app/go_waf/internal/versions/version.go
package versions

func IsAllowed(version string) bool {
	// TODO: Implement parsing and check rules from version_rules.png
	return true
}
EOF

    # Create Corpora
    echo '{"version": "1.4.0", "payload": "hello"}' > /app/corpora/clean/req1.json
    echo '{"version": "1.5.2", "payload": "world"}' > /app/corpora/clean/req2.json
    echo '{"version": "1.9.9", "payload": "test"}' > /app/corpora/clean/req3.json
    echo '{"version": "1.4.1", "payload": "safe"}' > /app/corpora/clean/req4.json
    echo '{"version": "1.8.0", "payload": "data"}' > /app/corpora/clean/req5.json

    echo '{"version": "1.3.9", "payload": "hello"}' > /app/corpora/evil/req1.json
    echo '{"version": "2.0.0", "payload": "world"}' > /app/corpora/evil/req2.json
    echo '{"version": "1.5.0", "payload": "DROP TABLE users;"}' > /app/corpora/evil/req3.json
    echo '{"version": "1.6.0", "payload": "<script>alert(1)</script>"}' > /app/corpora/evil/req4.json
    echo '{"version": "1.2.0", "payload": "DROP TABLE"}' > /app/corpora/evil/req5.json

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
