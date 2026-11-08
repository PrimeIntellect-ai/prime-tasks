#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git wget curl
    pip3 install pytest

    # Install Go 1.21+
    wget https://go.dev/dl/go1.21.6.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz
    rm go1.21.6.linux-amd64.tar.gz
    export PATH=/usr/local/go/bin:$PATH

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/repos/data-model.git
    mkdir -p /home/user/bin
    mkdir -p /home/user/logs
    mkdir -p /app/cap-analyzer

    # Initialize bare git repo
    git init --bare /home/user/repos/data-model.git

    # Create Go source files
    cat << 'EOF' > /app/cap-analyzer/main.go
package main

import (
	"flag"
	"fmt"
	"os"
)

func main() {
	target := flag.String("target", "", "Target directory")
	flag.Parse()

	if *target == "" {
		fmt.Println("Missing --target")
		os.Exit(1)
	}

	size, err := WalkDir(*target)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("%d\n", size)
}
EOF

    cat << 'EOF' > /app/cap-analyzer/walker.go
package main

import (
	"os"
	"path/filepath"
)

func WalkDir(root string) (int64, error) {
	var totalSize int64
	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		if !info.IsDir() {
			totalSize += info.Size()
		}
		if info.Mode()&os.ModeSymlink != 0 {
			target, _ := filepath.EvalSymlinks(path)
			if target != path && target != "" {
				s, _ := WalkDir(target)
				totalSize += s
			}
		}
		return nil
	})
	return totalSize, err
}
EOF

    cd /app/cap-analyzer
    go mod init cap-analyzer

    # Set permissions
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app/cap-analyzer
