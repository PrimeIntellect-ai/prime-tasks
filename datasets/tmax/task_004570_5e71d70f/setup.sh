#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/logs

# Create log files
cat << 'EOF' > /home/user/logs/app1.log
2023-10-01 INFO Starting application
2023-10-01 WARN High memory usage detected
2023-10-01 ERROR Failed to connect to DB
2023-10-01 INFO Retrying connection
EOF

cat << 'EOF' > /home/user/logs/app2.log
2023-10-02 INFO User login successful
2023-10-02 INFO Processing user data
2023-10-02 WARN Deprecated API usage
2023-10-02 ERROR Unexpected payload format
2023-10-02 FATAL Out of memory
EOF

cat << 'EOF' > /home/user/logs/app3.log
2023-10-03 INFO System shutdown initiated
2023-10-03 WARN Unsaved changes will be lost
2023-10-03 INFO Shutdown complete
EOF

# Create memory dump
head -c 1024 /dev/urandom > /home/user/crash.dump
echo -n "CRITICAL_CORRUPT: x9F2kL0m" >> /home/user/crash.dump
head -c 512 /dev/urandom >> /home/user/crash.dump

# Create buggy Go script
cat << 'EOF' > /home/user/log_processor.go
package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"strings"
	"sync"
)

var counts = make(map[string]int)

func processFile(filepath string, wg *sync.WaitGroup) {
	defer wg.Done()
	content, err := ioutil.ReadFile(filepath)
	if err != nil {
		return
	}
	lines := strings.Split(string(content), "\n")

	// Bug 2: Off-by-one error, misses the last line
	for i := 0; i < len(lines)-1; i++ {
		line := strings.TrimSpace(lines[i])
		if line == "" {
			continue
		}
		parts := strings.Split(line, " ")
		if len(parts) >= 2 {
			level := parts[1]
			// Bug 1: Race condition
			counts[level]++
		}
	}
}

func main() {
	files, _ := ioutil.ReadDir("/home/user/logs")
	var wg sync.WaitGroup
	for _, f := range files {
		wg.Add(1)
		go processFile("/home/user/logs/"+f.Name(), &wg)
	}
	wg.Wait()

	out, _ := json.Marshal(counts)
	ioutil.WriteFile("/home/user/final_counts.json", out, 0644)
	fmt.Println("Processing complete")
}
EOF

chmod -R 777 /home/user
