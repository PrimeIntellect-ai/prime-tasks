#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential cargo rustc
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/raw_logs/nested_1
    mkdir -p /home/user/raw_logs/nested_2
    mkdir -p /app

    # Create log files
    cat << 'EOF' > /home/user/raw_logs/nested_1/app1.log
[25-10-2023 10:15:30] ERROR Database connection failed
  at line 45
  at main module
[25-10-2023 10:16:00] INFO Retrying...
END_OF_TRANSACTION
EOF

    cat << 'EOF' > /home/user/raw_logs/nested_2/app2.log
[2023-10-26 11:00:00] INFO Startup
END_OF_TRANSACTION
EOF

    cat << 'EOF' > /home/user/raw_logs/nested_2/app3.log
[2023-10-27 09:00:00] WARN Memory low
EOF

    # Create legacy verifier C source
    cat << 'EOF' > /tmp/verifier.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <regex.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    char line[1024];
    int has_end = 0;
    regex_t regex;
    if (regcomp(&regex, "^\\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\\]", REG_EXTENDED)) return 1;

    while (fgets(line, sizeof(line), f)) {
        if (strstr(line, "END_OF_TRANSACTION")) {
            has_end = 1;
        }
        if (line[0] == '[') {
            if (regexec(&regex, line, 0, NULL, 0)) {
                return 1;
            }
        }
    }
    fclose(f);
    regfree(&regex);
    if (!has_end) return 1;
    return 0;
}
EOF

    # Compile and strip verifier
    gcc -O2 /tmp/verifier.c -o /app/legacy_verifier
    strip /app/legacy_verifier
    chmod +x /app/legacy_verifier

    # Clean up
    rm /tmp/verifier.c

    chmod -R 777 /home/user
