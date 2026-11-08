#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang espeak ffmpeg build-essential wget
    pip3 install pytest

    mkdir -p /home/user/src/audio-forensics
    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    # Create dummy Go codebase
    cat << 'EOF' > /home/user/src/audio-forensics/main.go
package main

import (
	"fmt"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: audio-detector <path_to_wav>")
		os.Exit(2)
	}
	// Broken implementation
	os.Exit(1)
}
EOF

    # Generate evidence audio file using espeak
    espeak -w /app/evidence_042.wav "PROJECT OVERSEER HAS BEEN COMPROMISED WE NEED IMMEDIATE EVACUATION"

    # Generate corpora audio files
    espeak -w /app/corpora/clean/clean1.wav "Normal audio baseline"
    espeak -w /app/corpora/evil/evil1.wav "Hidden steganographic anomaly detected"

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
