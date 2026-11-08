#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make cron
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create required directories
    mkdir -p /app/log-masker-1.0.0
    mkdir -p /home/user/corpus/clean
    mkdir -p /home/user/corpus/evil
    mkdir -p /home/user/incoming
    mkdir -p /home/user/outgoing

    # Create the C source file for the masker tool
    cat << 'EOF' > /app/log-masker-1.0.0/masker.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <regex.h>

void do_replace(char *line, const char *pattern, const char *replacement) {
    regex_t regex;
    regmatch_t pmatch[1];
    if (regcomp(&regex, pattern, REG_EXTENDED) != 0) return;
    while (regexec(&regex, line, 1, pmatch, 0) == 0) {
        char buf[4096];
        int start = pmatch[0].rm_so;
        int end = pmatch[0].rm_eo;
        strncpy(buf, line, start);
        buf[start] = '\0';
        strcat(buf, replacement);
        strcat(buf, line + end);
        strcpy(line, buf);
    }
    regfree(&regex);
}

int main(int argc, char **argv) {
    FILE *f = stdin;
    if (argc > 1) {
        f = fopen(argv[1], "r");
        if (!f) {
            perror("Error opening file");
            return 1;
        }
    }
    char line[4096];
    while (fgets(line, sizeof(line), f)) {
        do_replace(line, "api_key=[a-zA-Z0-9]\\{32\\}", "api_key=[REDACTED]");
        do_replace(line, "ssn=[0-9]\\{9\\}", "ssn=[REDACTED]");
        printf("%s", line);
    }
    if (f != stdin) fclose(f);
    return 0;
}
EOF

    # Create the broken Makefile (using spaces instead of tabs)
    cat << 'EOF' > /app/log-masker-1.0.0/Makefile
masker: masker.c
    gcc -O2 -o masker masker.c
EOF

    # Populate clean corpus
    cat << 'EOF' > /home/user/corpus/clean/1.log
timestamp=1678886400 metric=cpu_usage host=app-1 value=45.2
EOF

    # Populate evil corpus
    cat << 'EOF' > /home/user/corpus/evil/1.log
timestamp=1678886400 metric=request_latency host=app-1 api_key=a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4 value=120
timestamp=1678886405 metric=user_signup ssn=123456789 value=1
EOF

    # Set permissions
    chmod -R 777 /app/log-masker-1.0.0
    chmod -R 777 /home/user
