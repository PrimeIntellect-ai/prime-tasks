#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /app/graph-backup-extractor-v2.1.0
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    cat << 'EOF' > /app/graph-backup-extractor-v2.1.0/Makefile
build:
    go build -o bin/extractor main.go config.go
EOF

    cat << 'EOF' > /app/graph-backup-extractor-v2.1.0/config.go
package main

import "os"

type Config struct {
	Uri string
}

func LoadConfig() Config {
	return Config{
		//Uri: os.Getenv("NEO4J_URI"),
	}
}
EOF

    cat << 'EOF' > /app/graph-backup-extractor-v2.1.0/main.go
package main

import "fmt"

func main() {
	cfg := LoadConfig()
	fmt.Println("Starting extractor with URI:", cfg.Uri)
}
EOF

    cd /app/graph-backup-extractor-v2.1.0
    go mod init graph-backup-extractor

    for i in $(seq 1 50); do
        echo '{"safe": true}' > /app/corpora/clean/doc_$i.json
        echo '{"$where": "function() { return true; }", "ssn": "123-45-6789"}' > /app/corpora/evil/doc_$i.json
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
