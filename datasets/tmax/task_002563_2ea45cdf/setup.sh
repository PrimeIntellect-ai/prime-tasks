#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr golang-go
    pip3 install pytest pillow

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil
    mkdir -p /home/user

    # Generate evidence.png
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (200, 50), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), 'SYNC_SEED: 1.045', fill=(0,0,0))
img.save('/app/evidence.png')
"

    # Create buggy timeline.go
    cat << 'EOF' > /home/user/timeline.go
package main

import (
	"fmt"
)

type LogEntry struct {
	Timestamp float32
	Message   string
}

func sortLogs(logs []LogEntry) {
	// Buggy quicksort without proper base case/partition logic
	if len(logs) == 0 {
		return
	}
	pivot := logs[0].Timestamp
	left := []LogEntry{}
	right := []LogEntry{}
	for _, log := range logs {
		if log.Timestamp < pivot {
			left = append(left, log)
		} else {
			right = append(right, log)
		}
	}
	sortLogs(left)
	sortLogs(right)
}

func main() {
	fmt.Println("Timeline parser")
}
EOF

    # Generate clean corpus
    for i in $(seq 1 50); do
        cat << 'EOF' > /app/corpus/clean/log_${i}.txt
1000.000 Service started
1001.000 User logged in
1002.000 Action performed
1003.000 User logged out
EOF
    done

    # Generate evil corpus
    for i in $(seq 1 50); do
        cat << 'EOF' > /app/corpus/evil/log_${i}.txt
1000.000 Service started
1001.000 User logged in
1000.400 Suspicious activity
1003.000 User logged out
EOF
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
