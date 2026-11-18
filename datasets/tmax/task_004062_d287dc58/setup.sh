#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install necessary packages for the task
    apt-get install -y golang ffmpeg gcc build-essential
    pip3 install websockets

    # Create directories
    mkdir -p /app
    mkdir -p /home/user/app/lib
    mkdir -p /home/user/app/streamer
    mkdir -p /home/user/app/stateparser

    # Generate the video fixture
    cd /app
    ffmpeg -y -f lavfi -i color=c=0xC8C8C8:d=2:r=24:s=100x100 -c:v libx264 part1.mp4
    ffmpeg -y -f lavfi -i color=c=0x3232C8:d=3:r=24:s=100x100 -c:v libx264 part2.mp4
    ffmpeg -y -f lavfi -i color=c=0x32C832:d=5:r=24:s=100x100 -c:v libx264 part3.mp4
    echo "file 'part1.mp4'" > list.txt
    echo "file 'part2.mp4'" >> list.txt
    echo "file 'part3.mp4'" >> list.txt
    ffmpeg -y -f concat -safe 0 -i list.txt -c copy ui_test.mp4
    rm part1.mp4 part2.mp4 part3.mp4 list.txt

    # Create C library
    cat << 'EOF' > /home/user/app/lib/color.h
int GetColorState(unsigned char r, unsigned char g, unsigned char b);
EOF

    cat << 'EOF' > /home/user/app/lib/color.c
#include "color.h"
int GetColorState(unsigned char r, unsigned char g, unsigned char b) {
    if (r > 150 && g > 150 && b > 150) return 0; // Idle
    if (b > 150 && r < 100 && g < 100) return 1; // Loading
    if (g > 150 && r < 100 && b < 100) return 2; // Success
    return -1;
}
EOF

    cd /home/user/app/lib
    gcc -shared -o libcolor.so -fPIC color.c

    # Create Go project files
    cat << 'EOF' > /home/user/app/main.go
package main

import (
	"fmt"
	"net/http"
	"app/streamer"
)

func main() {
	http.HandleFunc("/ws", streamer.HandleWS)
	fmt.Println("Starting server on :8080")
	http.ListenAndServe(":8080", nil)
}
EOF

    cat << 'EOF' > /home/user/app/streamer/ws.go
package streamer

import (
	"net/http"
	"app/stateparser"
)

func HandleWS(w http.ResponseWriter, r *http.Request) {
    stateparser.Parse()
}
EOF

    cat << 'EOF' > /home/user/app/stateparser/parser.go
package stateparser

/*
#cgo CFLAGS: -I../lib
#cgo LDFLAGS: -L../lib -lcolor
#include "color.h"
*/
import "C"

import (
	"app/streamer"
)

func Parse() {
    // Circular import issue
    _ = streamer.HandleWS

    // Broken cgo call (using C.int instead of C.uchar)
    var r, g, b int = 200, 200, 200
    _ = C.GetColorState(C.int(r), C.int(g), C.int(b))
}
EOF

    cd /home/user/app
    go mod init app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
