#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    # Create necessary directories
    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    # Generate the audio briefing using espeak
    espeak -w /app/briefing.wav "The attacker is exploiting the authentication endpoint. You need to block any request where the path exactly matches '/auth/login' and the body contains a 'username' field that starts with 'admin_'."

    # Generate the JSON corpora
    python3 -c '
import json
import os

# Clean files
for i in range(10):
    with open(f"/app/corpora/clean/clean_{i}.json", "w") as f:
        if i % 2 == 0:
            json.dump({"method": "POST", "path": "/auth/login", "headers": {}, "body": {"username": f"user_{i}"}}, f)
        else:
            json.dump({"method": "POST", "path": "/data", "headers": {}, "body": {"username": f"admin_test_{i}"}}, f)

# Evil files
for i in range(10):
    with open(f"/app/corpora/evil/evil_{i}.json", "w") as f:
        json.dump({"method": "POST", "path": "/auth/login", "headers": {}, "body": {"username": f"admin_{i}"}}, f)
'

    # Create the Go script
    cat << 'EOF' > /app/requester.go
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"
)

func worker(paths <-chan string, wg *sync.WaitGroup) {
	defer wg.Done()
	for p := range paths {
		fmt.Println("Processing:", p)
	}
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Provide a directory")
		return
	}
	dir := os.Args[1]
	paths := make(chan string, 100)
	var wg sync.WaitGroup

	for i := 0; i < 3; i++ {
		wg.Add(1)
		go worker(paths, &wg)
	}

	filepath.Walk(dir, func(path string, info os.FileInfo, err error) error {
		if !info.IsDir() {
			paths <- path
		}
		return nil
	})
	close(paths)
	wg.Wait()
}
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
