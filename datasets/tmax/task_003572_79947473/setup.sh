#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang strace
    pip3 install pytest

    mkdir -p /home/user/logs
    echo "log data 1" > /home/user/logs/app_1.log
    echo "log data 2" > /home/user/logs/app_2.log
    echo "log data 3" > /home/user/logs/app_3.log
    mkfifo /home/user/logs/system_metrics.log

    cat << 'EOF' > /home/user/log_processor.go
package main

import (
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"
	"sync"
)

func main() {
	logDir := "/home/user/logs"
	files, err := ioutil.ReadDir(logDir)
	if err != nil {
		fmt.Println("Error reading directory:", err)
		os.Exit(1)
	}

	var wg sync.WaitGroup
	for _, f := range files {
		wg.Add(1)
		go func(filename string) {
			defer wg.Done()
			path := filepath.Join(logDir, filename)

			// This will block indefinitely on the FIFO
			data, err := ioutil.ReadFile(path)
			if err == nil {
				fmt.Printf("Processed %d bytes from %s\n", len(data), filename)
			}
		}(f.Name())
	}

	wg.Wait()
	fmt.Println("All logs processed successfully.")
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
