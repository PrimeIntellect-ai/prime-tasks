#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make binutils
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/workspace
    mkdir -p /home/user/corpus/clean
    mkdir -p /home/user/corpus/evil
    mkdir -p /app/secret_corpus/clean
    mkdir -p /app/secret_corpus/evil

    # Create /app/legacy_filter
    cat << 'EOF' > /tmp/legacy_filter.c
#include <stdio.h>
#include <string.h>

int main() {
    char buffer[4096];
    if (fgets(buffer, sizeof(buffer), stdin) != NULL) {
        if (strstr(buffer, "FATAL:") != NULL || 
            strstr(buffer, "PANIC:") != NULL || 
            strstr(buffer, "CREDENTIALS=") != NULL) {
            return 1;
        }
    }
    return 0;
}
EOF
    gcc -o /app/legacy_filter /tmp/legacy_filter.c
    strip --strip-all /app/legacy_filter
    rm /tmp/legacy_filter.c

    # Create Makefile with spaces instead of tabs
    cat << 'EOF' > /home/user/workspace/Makefile
all:
    g++ -o log_filter main.cpp
EOF

    # Create old_logic.c
    cat << 'EOF' > /home/user/workspace/old_logic.c
#include <stdio.h>
#include <string.h>

int is_clean(const char* line) {
    if (strstr(line, "FATAL:") != NULL) {
        return 0;
    }
    return 1;
}
EOF

    # Create main.cpp
    cat << 'EOF' > /home/user/workspace/main.cpp
#include <iostream>
#include <string>

int main() {
    // TODO: read lines from std::cin
    // TODO: implement logic translated from old_logic.c
    // TODO: deduce missing rules from /app/legacy_filter
    return 0;
}
EOF

    # Create corpus files
    cat << 'EOF' > /home/user/corpus/evil/sample1.log
[2023-01-01] PANIC: system crashed
[2023-01-01] User logged in with CREDENTIALS=admin:password
[2023-01-01] FATAL: Out of memory
EOF

    cat << 'EOF' > /home/user/corpus/clean/sample1.log
[2023-01-01] INFO: System started successfully
[2023-01-01] WARNING: CPU usage high
[2023-01-01] DEBUG: User credentials validated securely
EOF

    cat << 'EOF' > /app/secret_corpus/evil/test.log
PANIC: database connection lost
Connecting with CREDENTIALS=secret
FATAL: core dumped
EOF

    cat << 'EOF' > /app/secret_corpus/clean/test.log
INFO: All systems operational
WARNING: Disk space low
DEBUG: credentials_loaded=true
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
