#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang gawk
pip3 install pytest

mkdir -p /home/user/logprocessor/processor
mkdir -p /home/user/data
cd /home/user/logprocessor

go mod init logprocessor

cat << 'EOF' > main.go
package main

import (
	"fmt"
	"logprocessor/processor"
	"os"
)

func main() {
	sum := processor.ProcessLogs("/home/user/data")
	os.WriteFile("/home/user/processed_output.txt", []byte(fmt.Sprintf("%d", sum)), 0644)
}
EOF

cat << 'EOF' > processor/process.go
package processor

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

var MemoryLeakCache = make(map[string][]byte)

func Run(dir string) int {
	files, _ := os.ReadDir(dir)
	totalSum := 0
	for _, f := range files {
		if !f.IsDir() {
			sum, err := processFile(filepath.Join(dir, f.Name()))
			if err != nil {
				fLog, _ := os.OpenFile("/home/user/corrupted_files.txt", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
				fLog.WriteString(filepath.Join(dir, f.Name()) + "\n")
				fLog.Close()
			} else {
				totalSum += sum
			}
		}
	}
	return totalSum
}

func processFile(path string) (int, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return 0, err
	}

	// MEMORY LEAK
	MemoryLeakCache[path] = data

	sum := 0
	lines := strings.Split(string(data), "\n")
	for _, line := range lines {
		if strings.TrimSpace(line) == "" {
			continue
		}
		parts := strings.Split(line, ",")

		// PANIC BUG: does not check len(parts) >= 2
		val, err := strconv.Atoi(strings.TrimSpace(parts[1]))
		if err != nil {
			continue
		}
		sum += val
	}
	return sum, nil
}
EOF

for i in $(seq 1 200); do
	val=$((i % 10))
	awk -v v="$val" 'BEGIN { for(j=0;j<1000;j++) print "id," v }' > "/home/user/data/log_$i.csv"
done

echo "bad_data_no_comma" > "/home/user/data/bad log.csv"

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/logprocessor /home/user/data
chmod -R 777 /home/user
