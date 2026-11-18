#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make gdb
pip3 install pytest

mkdir -p /home/user/log_processor
mkdir -p /home/user/data
mkdir -p /home/user/legacy_headers

# Create legacy string.h to cause a dependency conflict
cat << 'EOF' > /home/user/legacy_headers/string.h
#error "Legacy string.h should not be used. Dependency conflict."
EOF

# Create the C source code
cat << 'EOF' > /home/user/log_processor/processor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void process_line(char *line) {
    char *token = strtok(line, "|");
    if (!token) return;
    char *timestamp = token;

    token = strtok(NULL, "|");
    if (!token) return;
    char *level = token;

    token = strtok(NULL, "|");
    char *message = token;

    // Bug: if message is missing, token is NULL. strlen(NULL) causes segfault.
    if (strlen(message) > 100) {
        printf("Long message at %s\n", timestamp);
    }
}

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    char buffer[256];
    while (fgets(buffer, sizeof(buffer), f)) {
        char *nl = strchr(buffer, '\n');
        if (nl) *nl = '\0';
        char copy[256];
        strcpy(copy, buffer);
        process_line(copy);
    }
    fclose(f);
    return 0;
}
EOF

# Create the buggy Makefile
cat << 'EOF' > /home/user/log_processor/Makefile
all:
	gcc -I/home/user/legacy_headers -g -o log_processor processor.c
EOF

# Create the input log file
cat << 'EOF' > /home/user/data/input.log
2023-01-01 10:00:00|INFO|System started normally
2023-01-01 10:05:00|WARN|Memory usage high
2023-01-01 10:10:00|ERROR
2023-01-01 10:15:00|INFO|System stopped
EOF

# Generate the core dump using gdb to bypass kernel core_pattern restrictions
cd /home/user/log_processor
gcc -g -o log_processor processor.c
gdb -batch -ex "run" -ex "generate-core-file /home/user/core.dump" --args ./log_processor /home/user/data/input.log || true

if [ ! -f /home/user/core.dump ]; then
    touch /home/user/core.dump
fi

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
