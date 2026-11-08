#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /app/vendored/go-rollstat
    mkdir -p /app/data/clean
    mkdir -p /app/data/evil

    cat << 'EOF' > /app/vendored/go-rollstat/rollstat.go
//go:build production

package rollstat

type Window struct {
    values []float64
}

func NewWindow() *Window {
    return &Window{values: make([]float64, 0)}
}
EOF

    cat << 'EOF' > /app/vendored/go-rollstat/Makefile
build:
	go build -tags=prod
EOF

    cat << 'EOF' > /app/vendored/go-rollstat/go.mod
module github.com/fake/go-rollstat

go 1.18
EOF

    cat << 'EOF' > /app/data/clean/1.jsonl
{"ts": 100, "val": 50.0, "id": "A1"}
{"ts": 100, "val": 50.0, "id": "A1"}
{"ts": 102, "val": 60.0, "id": "A1"}
EOF

    cat << 'EOF' > /app/data/evil/1.jsonl
{"ts": -5, "val": 50.0, "id": "A1"}
{"ts": 105, "val": 150.0, "id": "A1"}
{"ts": 106, "val": 50.0, "id": "a1"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
