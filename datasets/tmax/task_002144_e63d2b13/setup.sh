#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

mkdir -p /home/user/pipeline
cd /home/user/pipeline

# 1. Create the C source for the binary
cat << 'EOF' > extractor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    char* key = getenv("STREAM_AUTH");
    if (!key || strcmp(key, "auth_v2_99x") != 0) {
        fprintf(stderr, "Authentication failed. Missing or invalid auth token.\n");
        return 1;
    }
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <stream_id>\n", argv[0]);
        return 1;
    }

    unsigned long seed = atoi(argv[1]);

    // Use a deterministic LCG to avoid glibc rand() differences
    for(int i = 0; i < 1000; i++) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        double rand_val = (double)seed / 2147483647.0; 
        // Generates large numbers with tiny variance
        double val = 100000000.0 + rand_val * 0.001;
        printf("%.9f\n", val);
    }
    return 0;
}
EOF

# Compile the binary and remove source
gcc -O2 extractor.c -o extractor.bin
rm extractor.c

# 2. Create the flawed Python script
cat << 'EOF' > analyze.py
import sys
import math

def process_stream():
    data = []
    for line in sys.stdin:
        try:
            data.append(float(line.strip()))
        except ValueError:
            continue

    n = len(data)
    if n == 0:
        print("No data")
        return

    # Naive population standard deviation
    sum_x = sum(data)
    sum_x2 = sum(x*x for x in data)

    variance = (sum_x2 - (sum_x**2) / n) / n

    stddev = math.sqrt(variance)
    print(f"StdDev: {stddev:.6f}")

if __name__ == "__main__":
    process_stream()
EOF

# 3. Create the crash log
cat << 'EOF' > crash.log
[2023-10-27 10:15:02] [INFO] Processing stream 4001... OK
[2023-10-27 10:15:05] [INFO] Processing stream 4002... OK
[2023-10-27 10:15:08] [INFO] Processing stream 4003... OK
[2023-10-27 10:15:11] [INFO] Processing stream 4004...
Traceback (most recent call last):
  File "/home/user/pipeline/analyze.py", line 26, in <module>
    process_stream()
  File "/home/user/pipeline/analyze.py", line 22, in process_stream
    stddev = math.sqrt(variance)
ValueError: math domain error
EOF

chmod +x extractor.bin analyze.py

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/pipeline
chmod -R 777 /home/user
