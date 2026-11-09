#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/input
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/input/feedback.csv
UserID,Region,LogText
U01,NA,Mon: [AppA] positive - none | Tue: [AppB] negative - E100 | Wed: [AppA] neutral - none
U02,EU,Mon: [AppC] positive - none | Fri: [AppA] negative - E500
U03,NA,Tue: [AppB] negative - E100 | Thu: [AppC] positive - none
U04,NA,Wed: [AppA] positive - none | Fri: [AppC] positive - none
U05,EU,Mon: [AppA] neutral - none | Tue: [AppB] negative - E200 | Wed: [AppB] negative - E201
U06,AS,Thu: [AppA] positive - none | Invalid text here | Fri: [AppC] neutral - none
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
