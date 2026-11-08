#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg golang-go espeak
    pip3 install pytest

    mkdir -p /app

    # Generate the audio file
    espeak -w /app/build_requirements.wav "For the new mobile asset pipeline, apply a custom checksum. First, XOR every incoming byte of the asset with the hex value zero x Five A (0x5A). After XORing the entire stream, calculate the standard CRC-32 checksum using the standard IEEE polynomial. Print the resulting 32-bit integer as hex."

    # Create and compile the oracle hasher
    cat << 'EOF' > /app/oracle.go
package main
import (
	"hash/crc32"
	"io"
	"os"
	"fmt"
)
func main() {
	data, _ := io.ReadAll(os.Stdin)
	for i := range data {
		data[i] ^= 0x5A
	}
	checksum := crc32.ChecksumIEEE(data)
	fmt.Printf("%08x\n", checksum)
}
EOF

    cd /app
    go build -o oracle_hasher oracle.go
    rm oracle.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
