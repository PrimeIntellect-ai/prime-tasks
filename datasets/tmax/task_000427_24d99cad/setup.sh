#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app /home/user/data

    # Create the legacy_extractor C source
    cat << 'EOF' > /tmp/legacy_extractor.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main() {
    char line[4096];
    while (fgets(line, sizeof(line), stdin)) {
        if (strstr(line, "\\u") != NULL) {
            int *p = NULL;
            *p = 1; // Crash!
        }

        char *ts_start = strstr(line, "\"timestamp\":\"");
        if (ts_start) {
            ts_start += 13;
            char *ts_end = strchr(ts_start, '"');
            if (ts_end) {
                *ts_end = '\0';
                int score = strlen(line) % 100;
                printf("%s,%d\n", ts_start, score);
            }
        }
    }
    return 0;
}
EOF

    # Compile and strip
    gcc -O2 /tmp/legacy_extractor.c -o /app/legacy_extractor
    strip /app/legacy_extractor
    chmod +x /app/legacy_extractor

    # Create the dataset
    cat << 'EOF' > /home/user/data/events.jsonl
{"timestamp":"2023-10-12T14:30:00Z", "message":"System boot normal"}
{"timestamp":"2023-10-12T14:31:00Z", "message":"Found user \u0041"}
{"timestamp":"2023-10-12T14:32:00Z", "message":"Disk usage at 45%"}
{"timestamp":"2023-10-12T14:33:00Z", "message":"Network error \u26A0"}
{"timestamp":"2023-10-12T14:34:00Z", "message":"Process killed"}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/data
    chmod -R 777 /home/user
