#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/uptime
    cd /home/user/uptime

    cat << 'EOF' > Makefile
CC=gcc
CFLAGS=-Wall -Werror -Werror=implicit-function-declaration
all: log_parser

log_parser: log_parser.c
	$(CC) $(CFLAGS) -o log_parser log_parser.c
EOF

    cat << 'EOF' > log_parser.c
#include <stdio.h>
#include <stdlib.h>
// MISSING: include string header to cause build failure

int main() {
    char buffer[1024];
    // We just simulate reading raw logs and outputting the parsed JSON.
    // In reality this would do complex string manipulation.
    while (fgets(buffer, sizeof(buffer), stdin) != NULL) {
        if (strlen(buffer) > 0) {
            // Ignore actual input, just output the static parsed JSON for this test
            printf("{\"region_us\": {\"east\": 45, \"west\": [10, 5, {\"node1\": 2}]}, \"region_eu\": [20, 15], \"region_ap\": 8}\n");
            break;
        }
    }
    return 0;
}
EOF

    cat << 'EOF' > aggregator.py
import sys
import json

def calculate_downtime(data):
    if isinstance(data, dict):
        total = 0
        for key, value in data.items():
            total += calculate_downtime(value)
        return total
    elif isinstance(data, list):
        total = 0
        for item in data:
            total += calculate_downtime(item)
        return total
    # MISSING BASE CASE: Should return the integer
    # else:
    #     return data
    # Instead, we just call it on itself or do nothing, causing recursion or returning None
    return calculate_downtime(data) # Bug: infinite recursion on base case

if __name__ == "__main__":
    input_data = sys.stdin.read()
    if not input_data.strip():
        sys.exit(0)
    parsed = json.loads(input_data)
    total = calculate_downtime(parsed)
    print(total)
EOF

    cat << 'EOF' > raw_logs.txt
PING 192.168.1.1 TIMEOUT
PING 192.168.1.2 TIMEOUT
EOF

    chown -R user:user /home/user/uptime
    chmod -R 777 /home/user
