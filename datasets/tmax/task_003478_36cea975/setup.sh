#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc strace
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/pipeline_diag
    cd /home/user/pipeline_diag

    cat << 'EOF' > aggregator.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    int count = atoi(argv[1]);
    double *data = malloc(count * sizeof(double));
    if (!data) return 1;

    // Read EXACTLY 'count' doubles. If fewer bytes arrive, it blocks.
    size_t read_items = fread(data, sizeof(double), count, stdin);
    if (read_items != count) {
        // This won't trigger if it just blocks waiting for pipe EOF/data
    }

    double sum = 0.0;
    for (int i = 0; i < count; i++) {
        sum += data[i];
    }
    printf("SUM: %.9f\n", sum);
    free(data);
    return 0;
}
EOF

    gcc -o aggregator aggregator.c
    chmod +x aggregator

    cat << 'EOF' > run_pipeline.py
import sys
import json
import struct
import subprocess

def flatten_data(nested_list):
    flat = []
    i = 0
    while i < len(nested_list):
        if isinstance(nested_list[i], list):
            flat.extend(flatten_data(nested_list[i]))
            # BUG: Missing i += 1 here, causing infinite loop if there's a nested list
        else:
            flat.append(nested_list[i])
            i += 1
    return flat

def main():
    if len(sys.argv) != 2:
        print("Usage: run_pipeline.py <input.json>")
        sys.exit(1)

    with open(sys.argv[1], 'r') as f:
        data = json.load(f)

    flat_data = flatten_data(data)

    # Send to aggregator
    p = subprocess.Popen(['./aggregator', str(len(flat_data))], stdin=subprocess.PIPE, stdout=subprocess.PIPE)

    for val in flat_data:
        # BUG: Packing as single precision float ('f') instead of double ('d')
        # This sends 4 bytes instead of 8 bytes. C binary waits for more bytes.
        p.stdin.write(struct.pack('f', val))

    p.stdin.close()

    # Process blocks here waiting for C program, which is blocked waiting for stdin
    result = p.stdout.read().decode('utf-8')
    print(result.strip())

if __name__ == '__main__':
    main()
EOF

    cat << 'EOF' > input.json
[
  1.123456789,
  [2.123456789, 3.123456789],
  4.123456789,
  [5.123456789]
]
EOF

    cat << 'EOF' > expected.txt
SUM: 15.617283945
EOF

    chmod -R 777 /home/user
