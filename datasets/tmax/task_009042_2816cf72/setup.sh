#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git gcc gdb
pip3 install pytest

useradd -m -s /bin/bash user || true

# 1. Git Repository Setup
mkdir -p /home/user/uptime_monitor
cd /home/user/uptime_monitor
git init
git config user.email "dev@example.com"
git config user.name "Dev"

echo '{"api_url": "http://localhost:8080/health", "token": "SRE_MONITOR_TOK_99281aB"}' > config.json
echo -e "import json\nprint('monitor')" > monitor.py
git add config.json monitor.py
git commit -m "Initial commit with config"

echo '{"api_url": "http://localhost:8080/health"}' > config.json
git add config.json
git commit -m "Remove sensitive token from config"

echo "Added logging" >> monitor.py
git add monitor.py
git commit -m "Update monitor script"

# 2. C Source Code
mkdir -p /home/user/ingestd_service
cd /home/user/ingestd_service
cat << 'EOF' > ingest.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void process_segments(char *data) {
    char *ptr = data;
    while (ptr != NULL && *ptr != '\0') {
        char *next_comma = strchr(ptr, ',');
        if (next_comma != NULL) {
            *next_comma = '\0';
            // BUG 2: If the segment is empty (e.g. consecutive commas), it doesn't advance past the comma properly in the loop if we just reset ptr.
            // Actually, let's make it a clear infinite loop if the segment length is 0.
            if (strlen(ptr) == 0) {
                // Infinite loop here because ptr is not advanced when empty
                continue; 
            }
            ptr = next_comma + 1;
        } else {
            if (strlen(ptr) == 0) continue; // infinite loop on trailing empty
            ptr = NULL;
        }
    }
}

void parse_log(const char *input) {
    char buffer[64];
    int i = 0;
    // BUG 1: Off-by-one error (i <= 64 instead of i < 63 to leave room for null terminator)
    while (input[i] != '\0' && i <= 64) {
        buffer[i] = input[i];
        i++;
    }
    buffer[i] = '\0'; // Causes buffer overflow if i is 64

    process_segments(buffer);
}

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    parse_log(argv[1]);
    printf("SUCCESS\n");
    return 0;
}
EOF

# 3. Core Dump Generation
gcc -g -O0 ingest.c -o ingestd
bash -c 'ulimit -c unlimited; ./ingestd "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" || true'
# Rename core dump if generated, otherwise touch to ensure file exists for testing
mv core* core 2>/dev/null || touch core

# 4. Verification Script
cat << 'EOF' > verify.sh
#!/bin/bash
cd /home/user/ingestd_service

# Test 1: Buffer overflow test
./ingestd "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "FAILED: Buffer overflow test crashed." > /home/user/verification.log
    exit 1
fi

# Test 2: Infinite loop test (timeout after 2 seconds)
timeout 2s ./ingestd "seg1,,seg2" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "FAILED: Infinite loop test hung or crashed." > /home/user/verification.log
    exit 1
fi

echo "ALL TESTS PASSED" > /home/user/verification.log
EOF
chmod +x verify.sh

chmod -R 777 /home/user
