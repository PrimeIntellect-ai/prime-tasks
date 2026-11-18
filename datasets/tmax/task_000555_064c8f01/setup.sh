#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang imagemagick ffmpeg
pip3 install pytest

# Create the video artifact
mkdir -p /app
cd /app
for i in 1 2 3 4 5 6 7 8; do
  color="black"
  # 10110010 -> 1:W, 2:B, 3:W, 4:W, 5:B, 6:B, 7:W, 8:B
  if [ "$i" = "1" ] || [ "$i" = "3" ] || [ "$i" = "4" ] || [ "$i" = "7" ]; then color="white"; fi
  convert -size 640x480 canvas:$color frame_${i}.png
done
ffmpeg -framerate 1 -i frame_%d.png -c:v libx264 -pix_fmt yuv420p /app/artifact_scan.mp4
rm frame_*.png

# Create the oracle
mkdir -p /verify
cat << 'EOF' > /verify/oracle_bin_parser.go
package main

import (
	"encoding/binary"
	"fmt"
	"io"
	"os"
	"syscall"
)

func main() {
	if len(os.Args) < 2 {
		os.Exit(1)
	}

	f, err := os.Open(os.Args[1])
	if err != nil {
		fmt.Print("INVALID")
		os.Exit(1)
	}
	defer f.Close()

	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_SH); err != nil {
		fmt.Print("INVALID")
		os.Exit(1)
	}
	defer syscall.Flock(int(f.Fd()), syscall.LOCK_UN)

	data, err := io.ReadAll(f)
	if err != nil || len(data) < 11 {
		fmt.Print("INVALID")
		os.Exit(1)
	}

	if string(data[0:4]) != "ARTF" || data[4] != 0x02 {
		fmt.Print("INVALID")
		os.Exit(1)
	}

	flags := data[5]
	kLen := int(data[6])

	if len(data) < 11+kLen {
		fmt.Print("INVALID")
		os.Exit(1)
	}

	embKey := data[7 : 7+kLen]
	pLen := binary.LittleEndian.Uint32(data[7+kLen : 11+kLen])

	if uint32(len(data)-(11+kLen)) < pLen {
		fmt.Print("INVALID")
		os.Exit(1)
	}

	payload := data[11+kLen : 11+kLen+int(pLen)]
	out := make([]byte, pLen)
	copy(out, payload)

	masterKey := byte(0xB2)

	for i := 0; i < len(out); i++ {
		if (flags & 0x01) != 0 && kLen > 0 {
			out[i] ^= embKey[i%kLen]
		}
		if (flags & 0x02) != 0 {
			out[i] ^= masterKey
		}
	}

	os.Stdout.Write(out)
	os.Exit(0)
}
EOF

cd /verify
go build -o oracle_bin_parser oracle_bin_parser.go

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
