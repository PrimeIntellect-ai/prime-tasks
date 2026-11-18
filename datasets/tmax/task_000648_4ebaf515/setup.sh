#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest

    # Create directories
    mkdir -p /app/wal_clean /app/wal_evil
    mkdir -p /home/user/recovery_src

    # Generate wiki snapshot image
    convert -size 1000x200 xc:white -font DejaVu-Sans -pointsize 20 -fill black \
        -annotate +10+50 "SRE Wiki - Uptime DB WAL." \
        -annotate +10+100 "The WAL header must always start with the magic bytes 0xDEADBEEF to prevent parsing fragmented blocks." \
        /app/wiki_snapshot.png

    # Create go.mod with dependency conflict
    cat << 'EOF' > /home/user/recovery_src/go.mod
module recovery

go 1.18

require golang.org/x/sync v0.0.0-20210220032951-036812b2e83c
require golang.org/x/sync v0.1.0
EOF

    # Create recovery.go with deadlock and placeholder magic header
    cat << 'EOF' > /home/user/recovery_src/recovery.go
package main

import (
	"fmt"
	"io/ioutil"
	"os"
	"strings"
	"sync"
)

const MAGIC_HEADER = "0x00000000" // TODO: Update from wiki

func process(file string, wg *sync.WaitGroup, ch chan<- string, mu *sync.Mutex) {
	defer wg.Done()

	mu.Lock()
	// Bug: double lock causing deadlock
	mu.Lock()

	content, err := ioutil.ReadFile(file)
	if err != nil {
		mu.Unlock()
		return
	}

	if !strings.HasPrefix(string(content), MAGIC_HEADER) {
		mu.Unlock()
		return
	}

	ch <- "processed"
	mu.Unlock()
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: wal_sanitizer <filepath>")
		os.Exit(1)
	}

	filepath := os.Args[1]

	var wg sync.WaitGroup
	var mu sync.Mutex
	ch := make(chan string, 10)

	wg.Add(1)
	go process(filepath, &wg, ch, &mu)

	wg.Wait()
	close(ch)

	content, err := ioutil.ReadFile(filepath)
	if err != nil {
		fmt.Println("CORRUPTED")
		os.Exit(1)
	}

	if strings.HasPrefix(string(content), MAGIC_HEADER) && strings.Contains(string(content), "valid") {
		fmt.Println("VALID")
		os.Exit(0)
	} else {
		fmt.Println("CORRUPTED")
		os.Exit(1)
	}
}
EOF

    # Create clean WAL files
    for i in 1 2 3 4 5; do
        echo "0xDEADBEEF valid record $i" > /app/wal_clean/file${i}.wal
    done

    # Create evil WAL files
    echo "0xDEADBEEF invalid syntax" > /app/wal_evil/file1.wal
    echo "missing header completely" > /app/wal_evil/file2.wal
    echo "0xDEADBEEF valid ../../../etc/passwd" > /app/wal_evil/file3.wal
    echo "0xDEADBEEF" > /app/wal_evil/file4.wal
    echo "0xDEADBEEF corrupted data block" > /app/wal_evil/file5.wal

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
