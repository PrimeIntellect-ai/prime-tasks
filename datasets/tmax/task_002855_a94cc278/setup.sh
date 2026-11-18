#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb ltrace binutils
    pip3 install pytest

    mkdir -p /home/user/logs
    cd /home/user

    # Create legacy library source and compile it
    cat << 'EOF' > libfilter.c
#include <stdio.h>
#include <string.h>

int filter_log(const char* log_line) {
    char buffer[64];
    const char* prefix = "REQ_ID:";
    char* found = strstr(log_line, prefix);
    if (found) {
        // Vulnerability: strcpy without length check. 
        // Crash occurs if the REQ_ID value is >= 64 bytes.
        strcpy(buffer, found + strlen(prefix));
        return 1;
    }
    return 0;
}
EOF

    gcc -shared -fPIC -o libfilter.so libfilter.c
    rm libfilter.c

    # Create log_ingestor.c
    cat << 'EOF' > log_ingestor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

extern int filter_log(const char* log_line);

int main(int argc, char** argv) {
    if (argc < 2) {
        printf("Usage: %s <log_file>\n", argv[0]);
        return 1;
    }
    FILE* f = fopen(argv[1], "r");
    if (!f) return 1;
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        // TODO: Add sanitization and assertion here
        filter_log(line);
    }
    fclose(f);
    return 0;
}
EOF

    # Create log files
    echo "INFO User logged in" > logs/app_01.log
    echo "REQ_ID:12345 Processed successfully" >> logs/app_01.log
    echo "WARN Timeout occurred" > logs/app_02.log
    # Crashing log: REQ_ID payload is 70 'A's, exceeding the 63 char limit for the 64 byte buffer.
    echo "ERROR Connection lost" > logs/app_03.log
    echo "REQ_ID:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" >> logs/app_03.log
    echo "INFO Retrying..." >> logs/app_03.log

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
