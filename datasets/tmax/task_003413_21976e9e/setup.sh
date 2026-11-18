#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg golang
pip3 install pytest Pillow

mkdir -p /app
mkdir -p /home/user

# Generate video frames and compile video
cat << 'EOF' > /tmp/gen_frames.py
from PIL import Image
import os

os.makedirs('/tmp/frames', exist_ok=True)
white_frames = {120, 245, 301, 450, 512}

for i in range(600):
    color = (255, 255, 255) if i in white_frames else (0, 0, 0)
    img = Image.new('RGB', (64, 64), color)
    img.save(f'/tmp/frames/frame_{i:04d}.png')
EOF

python3 /tmp/gen_frames.py
ffmpeg -y -framerate 60 -i /tmp/frames/frame_%04d.png -c:v libx264 -pix_fmt yuv420p /app/dashboard_sync.mp4

# Generate raw_events.csv
cat << 'EOF' > /home/user/raw_events.csv
sync_id,vehicle_id,checkpoint_id,timestamp
10,V1,C9,999
120,V1,C1,1000
245,V1,C2,1010
301,V2,C1,1020
450,V1,C3,1030
512,V2,C2,1040
600,V1,C4,1050
EOF

# Generate oracle_query
cat << 'EOF' > /tmp/oracle.go
package main

import (
	"fmt"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("NOT_FOUND")
		return
	}
	vid := os.Args[1]
	if vid == "V1" {
		fmt.Println("C1,C2,C3")
	} else if vid == "V2" {
		fmt.Println("C1,C2")
	} else {
		fmt.Println("NOT_FOUND")
	}
}
EOF

go build -o /app/oracle_query /tmp/oracle.go

useradd -m -s /bin/bash user || true
chmod -R 777 /app
chmod -R 777 /home/user
