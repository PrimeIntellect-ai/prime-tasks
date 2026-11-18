#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg wget tar
pip3 install pytest numpy opencv-python-headless

# Install Go 1.21+
wget https://go.dev/dl/go1.21.6.linux-amd64.tar.gz
tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz
ln -s /usr/local/go/bin/go /usr/bin/go
rm go1.21.6.linux-amd64.tar.gz

# Generate video
mkdir -p /app
cat << 'EOF' > /app/generate_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/simulation.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (400, 400))
np.random.seed(42)
dots = np.random.rand(50, 2) * 400
velocities = (np.random.rand(50, 2) - 0.5) * 5

for frame in range(300):
    img = np.ones((400, 400, 3), dtype=np.uint8) * 255
    if frame < 150:
        dots += velocities
    else:
        for i in range(50):
            if i < 25:
                dots[i] += (np.array([100, 100]) - dots[i]) * 0.05
            else:
                dots[i] += (np.array([300, 300]) - dots[i]) * 0.05
    dots = np.clip(dots, 0, 399)
    for i in range(50):
        cv2.circle(img, (int(dots[i,0]), int(dots[i,1])), 5, (0, 0, 0), -1)
    out.write(img)
out.release()
EOF
python3 /app/generate_video.py

# Create user and pipeline
useradd -m -s /bin/bash user || true
mkdir -p /home/user/pipeline

cat << 'EOF' > /home/user/pipeline/main.go
package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os/exec"
	"time"
)

type Result struct {
	MaxEffectiveResistance float64 `json:"max_effective_resistance"`
	KLDivergence0Vs299     float64 `json:"kl_divergence_0_vs_299"`
	RuntimeSeconds         float64 `json:"runtime_seconds"`
}

func main() {
	start := time.Now()
	fmt.Println("Extracting frames...")
	cmd := exec.Command("ffmpeg", "-y", "-i", "/app/simulation.mp4", "-f", "image2", "/tmp/frame_%03d.png")
	cmd.Run()

	// Deliberately slow and unstable logic
	time.Sleep(20 * time.Second)

	res := Result{
		MaxEffectiveResistance: 0.0,
		KLDivergence0Vs299:     0.0,
		RuntimeSeconds:         time.Since(start).Seconds(),
	}

	file, _ := json.MarshalIndent(res, "", " ")
	ioutil.WriteFile("/home/user/results.json", file, 0644)
}
EOF

cd /home/user/pipeline
go mod init pipeline
go get gonum.org/v1/gonum/mat@v0.14.0 || true

chmod -R 777 /home/user
