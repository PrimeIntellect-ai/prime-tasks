#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg build-essential golang-go cargo rustc
pip3 install pytest

# Create user
useradd -m -s /bin/bash user || true

mkdir -p /app/corpora/evil /app/corpora/clean
mkdir -p /home/user/tools/analyzer
mkdir -p /home/user/dispatcher

# Generate dummy video (14s blue, 1s red, 5s blue)
ffmpeg -f lavfi -i color=c=blue:s=320x240:d=14 -f lavfi -i color=c=red:s=320x240:d=1 -f lavfi -i color=c=blue:s=320x240:d=5 -filter_complex "[0:v][1:v][2:v]concat=n=3:v=1[v]" -map "[v]" /app/test_run.mp4

# Create C++ analyzer
cat << 'EOF' > /home/user/tools/analyzer/main.cpp
#include <iostream>
#include <fstream>
#include <vector>

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    std::ifstream file(argv[1], std::ios::binary | std::ios::ate);
    if (!file) return 1;
    std::streamsize size = file.tellg();
    file.seekg(0, std::ios::beg);
    std::vector<char> buffer(size);
    if (file.read(buffer.data(), size)) {
        // Bug: out of bounds read
        for (int i = 0; i <= size; ++i) {
            // Dummy logic to simulate error state on frame 14/15
            if (i < size && buffer[i] == 'R') {
                std::cout << "STATE=UI_ERROR_MODAL\n";
                return 0;
            }
        }
    }
    std::cout << "STATE=OK\n";
    return 0;
}
EOF

# Create Go dispatcher
cat << 'EOF' > /home/user/dispatcher/main.go
package main

import (
	"sync"
)

type Dispatcher struct {
	Results []string
}

func (d *Dispatcher) RunJobs(jobs []string) {
	var wg sync.WaitGroup
	for _, job := range jobs {
		wg.Add(1)
		go func(j string) {
			defer wg.Done()
			// Data race
			d.Results = append(d.Results, j+"_done")
		}(job)
	}
	wg.Wait()
}
EOF

cat << 'EOF' > /home/user/dispatcher/main_test.go
package main

import "testing"

func TestRunJobs(t *testing.T) {
	d := &Dispatcher{}
	jobs := []string{"job1", "job2", "job3", "job4", "job5"}
	d.RunJobs(jobs)
	if len(d.Results) != len(jobs) {
		t.Errorf("Expected %d results, got %d", len(jobs), len(d.Results))
	}
}
EOF

# Create corpora
cat << 'EOF' > /app/corpora/evil/1.json
{"schema": "v1", "asset_path": "../../secret"}
EOF

cat << 'EOF' > /app/corpora/evil/2.json
{"schema": "v2", "asset_path": "/etc/passwd"}
EOF

cat << 'EOF' > /app/corpora/clean/1.json
{"schema": "v1", "asset_path": "./local/img.png"}
EOF

cat << 'EOF' > /app/corpora/clean/2.json
{"schema": "v2", "asset_path": "assets/logo.png"}
EOF

chmod -R 777 /home/user /app
