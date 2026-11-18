#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang ffmpeg
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/oracle.go
package main

import (
	"bufio"
	"encoding/binary"
	"io"
	"os"
)

func main() {
	reader := bufio.NewReader(os.Stdin)
	frameSize := 320 * 240 * 3
	buf := make([]byte, frameSize)

	for {
		_, err := io.ReadFull(reader, buf)
		if err != nil {
			break
		}

		var sumR, sumG, sumB uint64
		pixels := 0

		for y := 60; y < 180; y++ {
			for x := 80; x < 240; x++ {
				idx := (y*320 + x) * 3
				sumR += uint64(buf[idx])
				sumG += uint64(buf[idx+1])
				sumB += uint64(buf[idx+2])
				pixels++
			}
		}

		avgR := sumR / uint64(pixels)
		avgG := sumG / uint64(pixels)
		avgB := sumB / uint64(pixels)

		token := uint16((avgR>>4)<<8 | (avgG>>4)<<4 | (avgB >> 4))
		binary.Write(os.Stdout, binary.LittleEndian, token)
	}
}
EOF

    go build -o /app/oracle_tokenizer /tmp/oracle.go
    chmod +x /app/oracle_tokenizer

    ffmpeg -f lavfi -i testsrc=duration=10:size=320x240:rate=30 -vcodec libx264 -pix_fmt yuv420p -y /app/training_source.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
