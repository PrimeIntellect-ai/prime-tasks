#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/legacy_filter.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <regex.h>
#include <ctype.h>

int check_sqli(const char *str) {
    const char *target = "UNION SELECT";
    size_t target_len = strlen(target);
    size_t str_len = strlen(str);
    if (str_len < target_len) return 0;
    for (size_t i = 0; i <= str_len - target_len; i++) {
        int match = 1;
        for (size_t j = 0; j < target_len; j++) {
            if (toupper(str[i+j]) != target[j]) {
                match = 0;
                break;
            }
        }
        if (match) return 1;
    }
    return 0;
}

int check_cc(const char *str) {
    regex_t regex;
    int ret;
    const char *pattern = "(^|[^a-zA-Z0-9_])[0-9]{4}[- ]?[0-9]{4}[- ]?[0-9]{4}[- ]?[0-9]{4}([^a-zA-Z0-9_]|$)";
    if (regcomp(&regex, pattern, REG_EXTENDED) != 0) return 0;
    ret = regexec(&regex, str, 0, NULL, 0);
    regfree(&regex);
    return ret == 0;
}

int check_homoglyph(const char *str) {
    size_t len = strlen(str);
    for (size_t i = 0; i < len; i++) {
        if ((unsigned char)str[i] == 0xD0 && i + 1 < len && (unsigned char)str[i+1] == 0xBE) {
            int adj = 0;
            if (i > 0 && isalpha(str[i-1])) adj = 1;
            if (i + 2 < len && isalpha(str[i+2])) adj = 1;
            if (adj) return 1;
        }
    }
    return 0;
}

int main(int argc, char *argv[]) {
    if (argc < 2) return 0;
    if (check_sqli(argv[1])) return 1;
    if (check_cc(argv[1])) return 1;
    if (check_homoglyph(argv[1])) return 1;
    return 0;
}
EOF

    gcc -O3 -s /app/legacy_filter.c -o /app/legacy_filter
    rm /app/legacy_filter.c

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/train

    cat << 'EOF' > /home/user/train/sample.csv
1700000000,user_1,Hello there!
1700000010,user_1,My card is 1234-5678-1234-5678
1700000020,user_2,What about union select * from users?
1700000030,user_2,Normal message
1700000040,user_3,cоmputer
EOF

    chmod -R 777 /home/user
