#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go make
    pip3 install pytest

    # Create vendored library directory
    mkdir -p /app/vendored/statslib

    # Create gen.py
    cat << 'EOF' > /app/vendored/statslib/gen.py
import os
import sys
if os.environ.get("GEN_ALLOW") != "1":
    print("Error: GEN_ALLOW environment variable not set to 1")
    sys.exit(1)
with open("tables.go", "w") as f:
    f.write("package statslib\n\nfunc CalculateCI(data []float64) (float64, float64) {\n\t// Dummy implementation for task\n\tsum := 0.0\n\tfor _, v := range data { sum += v }\n\tmean := sum / float64(len(data))\n\treturn mean - 1.96, mean + 1.96\n}\n")
EOF

    # Create Makefile
    cat << 'EOF' > /app/vendored/statslib/Makefile
all: gen

gen:
	python3 gen.py
EOF

    # Create go.mod for statslib
    cat << 'EOF' > /app/vendored/statslib/go.mod
module github.com/local/statslib

go 1.18
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
