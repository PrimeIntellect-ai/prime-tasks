#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc golang-go
    pip3 install pytest

    # Create directories
    mkdir -p /app
    mkdir -p /corpus/clean
    mkdir -p /corpus/evil
    mkdir -p /home/user/samples

    # Create C source for legacy analyzer
    cat << 'EOF' > /tmp/analyzer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc < 2) return 0;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 0;
    char line[4096];
    while (fgets(line, sizeof(line), f)) {
        char *p = line;
        while ((p = strstr(p, "\\u"))) {
            int val;
            if (sscanf(p + 2, "%04x", &val) == 1) {
                if (val >= 0xD800 && val <= 0xDBFF) {
                    if (strncmp(p + 6, "\\u", 2) == 0) {
                        int val2;
                        if (sscanf(p + 8, "%04x", &val2) == 1) {
                            if (val2 >= 0xDC00 && val2 <= 0xDFFF) {
                                p += 12;
                                continue;
                            }
                        }
                    }
                    abort();
                } else if (val >= 0xDC00 && val <= 0xDFFF) {
                    abort();
                }
            }
            p += 2;
        }
    }
    fclose(f);
    return 0;
}
EOF

    # Compile and strip
    gcc -O2 /tmp/analyzer.c -o /app/legacy_analyzer
    strip /app/legacy_analyzer
    rm /tmp/analyzer.c

    # Generate corpus and samples
    cat << 'EOF' > /tmp/gen_data.py
import csv
import random
import os

def make_csv(path, is_evil, num_rows=10):
    with open(path, 'w', newline='') as f:
        writer = csv.writer(f)
        for i in range(num_rows):
            req_id = f"req_{random.randint(1000, 9999)}"
            group_id = f"group_{random.choice(['A', 'B', 'C', 'D'])}"
            timestamp = random.randint(1600000000, 1700000000)

            if is_evil and i == num_rows - 1:
                evil_seq = random.choice(['\\uD83D', '\\uDC00', '\\uD800'])
                data = '{"msg": "Hello ' + evil_seq + ' world"}'
            else:
                data = '{"msg": "Hello \\uD83D\\uDE00 world"}'

            writer.writerow([req_id, group_id, timestamp, data])

for i in range(100):
    make_csv(f'/corpus/clean/clean_{i}.csv', False)
    make_csv(f'/corpus/evil/evil_{i}.csv', True)

for i in range(2):
    make_csv(f'/home/user/samples/clean_{i}.csv', False)
    make_csv(f'/home/user/samples/evil_{i}.csv', True)
EOF
    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /corpus
    chmod -R 777 /app
