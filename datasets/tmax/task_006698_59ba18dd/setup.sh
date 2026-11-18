#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    mkdir -p /home/user/pipeline/data

    cat << 'EOF' > /home/user/pipeline/data/input.dat
ID: 1001
PROCESS: start_job
EVENT: trigger
PROCESS
PROCESS: end_job
EOF

    cat << 'EOF' > /home/user/pipeline/data_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 3) {
        printf("Usage: %s <input_file> <output_log>\n", argv[0]);
        return 1;
    }
    FILE *in = fopen(argv[1], "r");
    if (!in) {
        printf("Cannot open input file %s\n", argv[1]);
        return 1;
    }
    FILE *out = fopen(argv[2], "w");
    if (!out) {
        printf("Cannot open output file %s\n", argv[2]);
        fclose(in);
        return 1;
    }

    char buffer[256];
    fprintf(out, "2023-10-01T10:00:00|INFO|Starting processing\n");

    while (fgets(buffer, sizeof(buffer), in)) {
        buffer[strcspn(buffer, "\n")] = 0;
        char *colon = strchr(buffer, ':');

        if (strncmp(buffer, "PROCESS", 7) == 0) {
            // Bug: dereferencing colon + 1 when colon is NULL causes segfault
            char *val = colon + 1;
            fprintf(out, "2023-10-01T10:01:00|INFO|Processing item: %s\n", val);
        } else if (strncmp(buffer, "EVENT", 5) == 0) {
            fprintf(out, "2023-10-01T10:01:05|CRITICAL|Unexpected event found\n");
        }
    }
    fprintf(out, "2023-10-01T10:02:00|INFO|Processing complete\n");

    fclose(in);
    fclose(out);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/pipeline/log_analyzer.py
import sys
import json
from collections import defaultdict

def analyze(log_file, report_file):
    counts = {"INFO": 0, "WARN": 0, "ERROR": 0}
    with open(log_file, 'r') as f:
        for line in f:
            parts = line.strip().split('|')
            if len(parts) >= 2:
                level = parts[1].strip()
                # Bug: KeyError on 'CRITICAL' because it uses direct access without initializing new keys
                counts[level] += 1

    with open(report_file, 'w') as f:
        json.dump(counts, f)

if __name__ == '__main__':
    if len(sys.argv) < 3:
        sys.exit(1)
    analyze(sys.argv[1], sys.argv[2])
EOF

    cat << 'EOF' > /home/user/pipeline/run_pipeline.sh
#!/bin/bash
# Environment misconfiguration: wrong data directory
export DATA_DIR=/var/lib/pipeline/data

cd /home/user/pipeline
./data_parser $DATA_DIR/input.dat $DATA_DIR/app.log
if [ $? -eq 0 ]; then
    python3 log_analyzer.py $DATA_DIR/app.log $DATA_DIR/summary_report.json
else
    echo "Data parser failed."
    exit 1
fi
EOF

    chmod +x /home/user/pipeline/run_pipeline.sh
    cd /home/user/pipeline && gcc -o data_parser data_parser.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
