#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make strace ltrace
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/metrics_app/helper

    # 1. Broken Makefile and C file
    cat << 'EOF' > /home/user/metrics_app/helper/process_data.c
#include <stdio.h>
#include <math.h>
int main() {
    double result = sqrt(16.0);
    printf("Result: %f\n", result);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/metrics_app/helper/Makefile
all:
	gcc process_data.c -o process_data
EOF

    # 2. Legacy Submitter (C code, compiled to binary)
    cat << 'EOF' > /tmp/legacy_submitter.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char* token = getenv("SUBMIT_TOKEN");
    if (token != NULL && strcmp(token, "ALPHA99") == 0) {
        printf("Success\n");
        return 0;
    }
    printf("Auth Error\n");
    return 1;
}
EOF
    gcc /tmp/legacy_submitter.c -o /home/user/metrics_app/legacy_submitter
    chmod +x /home/user/metrics_app/legacy_submitter
    rm /tmp/legacy_submitter.c

    # 3. Buggy Bash Script
    cat << 'EOF' > /home/user/metrics_app/daemon.sh
#!/bin/bash

# Memory leak variable
LOG_CACHE=""

while true; do
    VAL1=10
    VAL2=20

    # Formula bug: calculates 10 + (20/2) = 20, instead of (10+20)/2 = 15
    AVG=$(( VAL1 + VAL2 / 2 ))

    # Memory leak: keeps appending indefinitely
    LOG_CACHE+="Processed avg: $AVG\n"

    # Call to legacy binary without auth
    /home/user/metrics_app/legacy_submitter

    sleep 1
    break # Just for testing purposes
done
EOF
    chmod +x /home/user/metrics_app/daemon.sh

    chown -R user:user /home/user/metrics_app
    chmod -R 777 /home/user
