#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv gcc make
    pip3 install pytest

    mkdir -p /home/user/legacy_pipeline

    cat << 'EOF' > /home/user/legacy_pipeline/requirements.txt
requests==2.24.0
urllib3==1.26.15
EOF

    cat << 'EOF' > /home/user/legacy_pipeline/Makefile
all:
	gcc -shared -o libfastcompute.so -fPIC fast_compute.c
EOF

    cat << 'EOF' > /home/user/legacy_pipeline/fast_compute.c
#include <string.h>
#include <math.h>

double compute_score(const char* input) {
    char buffer[128];
    // Vulnerability: strcpy overflows if input is 128 bytes or more (including null terminator, but practically 128 bytes of characters + null will overflow).
    // The exact string length of characters that overflows a 128 byte buffer is 128 (since it needs space for \0).
    strcpy(buffer, input);

    double val = 0;
    for(int i = 0; i < strlen(buffer); i++) {
        val += (double)buffer[i];
    }
    return sqrt(val);
}
EOF

    cat << 'EOF' > /home/user/legacy_pipeline/process_data.py
import ctypes
import threading
import os

# load lib
lib = ctypes.CDLL(os.path.abspath('libfastcompute.so'))
lib.compute_score.restype = ctypes.c_double
lib.compute_score.argtypes = [ctypes.c_char_p]

total_score = 0.0

def process_line(line):
    global total_score

    # Process line
    encoded = line.encode('utf-8')
    score = lib.compute_score(encoded)

    # RACE CONDITION: total_score += score is not thread-safe in Python without a lock
    total_score += score

def main():
    # Generate some dummy data, including a line that will crash the C extension
    lines = [
        "short line",
        "another normal line",
        "A" * 50,
        "B" * 128,  # This will trigger the buffer overflow
        "C" * 20
    ] * 100

    threads = []
    for line in lines:
        t = threading.Thread(target=process_line, args=(line,))
        threads.append(t)
        t.start()

    for t in threads:
        t.join()

    print(f"Final Score: {total_score}")

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
