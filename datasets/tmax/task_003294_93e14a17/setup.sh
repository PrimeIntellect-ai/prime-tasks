#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg golang
    pip3 install pytest

    mkdir -p /app
    ffmpeg -y -f lavfi -i testsrc=duration=10:size=640x360:rate=30 -c:v libx264 /app/cell_video.mp4 2>/dev/null

    cat << 'EOF' > /tmp/oracle.go
package main

import (
    "bufio"
    "fmt"
    "os"
    "strings"
)

func main() {
    // W = 640, F = 300
    W := 640
    F := 300
    alpha := 0.25

    scanner := bufio.NewScanner(os.Stdin)
    var seqBuilder strings.Builder
    for scanner.Scan() {
        line := scanner.Text()
        if strings.HasPrefix(line, ">") {
            continue
        }
        seqBuilder.WriteString(strings.TrimSpace(line))
    }

    L := float64(seqBuilder.Len())

    mesh := make([]float64, W)
    mesh[W/2] = L

    newMesh := make([]float64, W)

    for step := 0; step < F; step++ {
        for i := 1; i < W-1; i++ {
            newMesh[i] = mesh[i] + alpha*(mesh[i-1]-2*mesh[i]+mesh[i+1])
        }
        for i := 1; i < W-1; i++ {
            mesh[i] = newMesh[i]
        }
    }

    fmt.Printf("%.6f\n", mesh[W/2])
}
EOF
    go build -o /app/oracle_solver /tmp/oracle.go
    chmod +x /app/oracle_solver

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
