#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang strace
pip3 install pytest

mkdir -p /home/user/calc
mkdir -p /home/user/data

# 1. Create the vulnerable Go package
cat << 'EOF' > /home/user/calc/calc.go
package calc

func Calculate(data []byte) int {
	accumulator := 1
	for i := 0; i < len(data); i++ {
		if data[i] == ' ' || data[i] == '\n' {
			continue
		}
		if data[i] == '+' {
			if i+1 < len(data) {
				accumulator += int(data[i+1])
				i++
			}
		} else if data[i] == '*' {
			// BUG: Missing bounds check here
			accumulator *= int(data[i+1])
			i++
		} else {
			accumulator += int(data[i])
		}
	}
	return accumulator
}
EOF

cd /home/user/calc
go mod init calc

# 2. Create the black-box binary source and compile it
mkdir -p /home/user/worker_src
cat << 'EOF' > /home/user/worker_src/main.go
package main

import (
	"calc"
	"io/ioutil"
	"os"
	"path/filepath"
	"sort"
)

func main() {
	defer func() {
		if r := recover(); r != nil {
			os.Exit(1) // Silently crash
		}
	}()

	if len(os.Args) < 3 {
		os.Exit(0)
	}

	dir := os.Args[2]
	files, err := ioutil.ReadDir(dir)
	if err != nil {
		os.Exit(1)
	}

	// Sort to ensure deterministic processing order
	sort.Slice(files, func(i, j int) bool {
		return files[i].Name() < files[j].Name()
	})

	for _, f := range files {
		path := filepath.Join(dir, f.Name())
		data, err := ioutil.ReadFile(path)
		if err == nil {
			calc.Calculate(data)
		}
	}
}
EOF

cd /home/user/worker_src
go mod init worker
go mod edit -replace calc=/home/user/calc
go get calc
go build -o /home/user/math-worker main.go
rm -rf /home/user/worker_src

# 3. Create the data files
echo -n "1 + 2" > "/home/user/data/batch_A.txt"
echo -n "4 + 5" > "/home/user/data/batch_B.txt"
echo -n "7 *" > "/home/user/data/batch_C broken.txt"
echo -n "2 + 2" > "/home/user/data/batch_D.txt"

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
