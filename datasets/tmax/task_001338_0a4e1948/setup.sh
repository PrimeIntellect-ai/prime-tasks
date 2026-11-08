#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang g++ ffmpeg
    pip3 install pytest pyyaml

    mkdir -p /app/corpus/evil /app/corpus/clean
    mkdir -p /workspace/src/lib /workspace/bin

    # Generate a dummy video
    ffmpeg -f lavfi -i color=c=white:s=320x240:d=2 -vf "fps=30" /app/test_run.mp4

    # Create corpus files
    echo '{"event_id": 1, "signature": 142}' > /app/corpus/clean/1.json
    echo '{"event_id": 2, "signature": 284}' > /app/corpus/clean/2.json
    echo '{"event_id": 1, "signature": 0}' > /app/corpus/evil/1.json
    echo '!!python/object/apply:os.system ["echo evil"]' > /app/corpus/evil/2.json

    # Create C++ file
    cat << 'EOF' > /workspace/src/lib/analyzer.cpp
extern "C" {
    int calculate_brightness(unsigned char* data, int length) {
        long long total = 0;
        for (int i = 0; i <= length; i++) { // Bug: out of bounds
            total += data[i];
        }
        return total / length;
    }
}
EOF

    # Create Go file
    cat << 'EOF' > /workspace/src/main.go
package main

import (
	"fmt"
	"sync"
)

func main() {
	BrightFrameCount := 0
	var wg sync.WaitGroup
	for i := 0; i < 142; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			BrightFrameCount++ // Bug: race condition
		}()
	}
	wg.Wait()
	fmt.Println("BrightFrameCount:", BrightFrameCount)
}
EOF

    # Create legacy Python filter
    cat << 'EOF' > /workspace/legacy_filter.py
import yaml
import sys

print "Starting legacy filter..."

def is_clean_record(json_data, calibration_key):
    # TODO: implement
    return True

if __name__ == "__main__":
    with open(sys.argv[1], 'r') as f:
        data = yaml.load(f) # Unsafe load
        print data
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app /workspace
