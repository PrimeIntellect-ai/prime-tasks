#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int parse(const char *str) {
    int depth = 0;
    const char *ptr = str;
    while (*ptr != '\0') {
        if (*ptr == '[') {
            depth++;
            ptr++;
        } else if (*ptr == ']') {
            depth--;
            ptr++;
        } else if (*ptr == '*') {
            // BUG: Missing pointer increment inside the loop
            while (depth > 2) {
                if (*ptr != '*') break;
                // Intentional bug: ptr is not incremented here!
                // FIX: ptr++;
            }
            if (depth <= 2) {
                ptr++;
            }
        } else {
            ptr++;
        }
    }
    return depth == 0;
}

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    parse(argv[1]);
    printf("Success\n");
    return 0;
}
EOF

    gcc /home/user/parser.c -o /home/user/parser

    echo -n "abc[]*[][][][][][[[][][]]]*[][][]*[][][][][][[[*]]]" > /home/user/crash_input.txt

    chmod -R 777 /home/user
