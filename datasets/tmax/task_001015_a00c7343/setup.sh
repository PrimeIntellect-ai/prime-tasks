#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang ffmpeg git gcc libc6-dev
    pip3 install pytest

    mkdir -p /app

    # 1. Generate diagnostics.mp4 (5s, 30fps = 150 frames, frames 40-51 are red)
    ffmpeg -f lavfi -i "color=c=black:s=640x480:r=30:d=5" \
        -vf "drawbox=x=0:y=0:w=640:h=480:color=red@1:t=fill:enable='between(n,40,51)'" \
        -c:v libx264 -pix_fmt yuv420p /app/diagnostics.mp4

    # 2. Create Oracle Analyzer
    cat << 'EOF' > /app/oracle.go
package main

import (
    "fmt"
    "os"
    "strconv"
    "time"
)

func main() {
    if len(os.Args) != 2 {
        return
    }
    epoch, _ := strconv.ParseInt(os.Args[1], 10, 64)
    loc, _ := time.LoadLocation("America/New_York")
    t := time.Unix(epoch, 0).In(loc)

    res := time.Date(t.Year(), t.Month(), t.Day()+1, 0, 0, 0, 0, loc)
    fmt.Println(res.Unix())
}
EOF
    go build -o /app/oracle_analyzer /app/oracle.go
    rm /app/oracle.go

    # 3. Setup Git Repository
    mkdir -p /home/user/analyzer
    cd /home/user/analyzer
    git init --initial-branch=main
    git config user.email "test@example.com"
    git config user.name "Test"

    echo "# Analyzer" > README.md
    git add README.md
    git commit -m "Initial commit"

    git checkout -b feature/tz-fix-12

    cat << 'EOF' > main.go
package main

import (
    "fmt"
    "os"
    "strconv"
    "time"
)

// #include "utils.h"
import "C"

func main() {
    if len(os.Args) != 2 { return }
    epoch, _ := strconv.ParseInt(os.Args[1], 10, 64)
    loc, _ := time.LoadLocation("America/New_York")
    t := time.Unix(epoch, 0).In(loc)

    // Buggy convergence loop
    for {
        t = t.Add(24 * time.Hour)
        if t.Hour() == 0 {
            // Truncate minutes and seconds
            res := time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, loc)
            fmt.Println(res.Unix())
            return
        }
    }
}
EOF

    cat << 'EOF' > go.mod
module analyzer

go 1.18
EOF

    cat << 'EOF' > utils.h
void do_nothing();
EOF

    cat << 'EOF' > utils.c
#include "utils.h"
void do_nothing() {
    SYNTAX ERROR DELIBERATE LINKER FAIL
}
EOF

    git add main.go go.mod utils.h utils.c
    git commit -m "Add timezone logic with CGO dependency"
    git checkout main

    # 4. User Setup
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
