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

int is_palindrome(const char *word) {
    int len = strlen(word);
    if (len < 2) return 0;
    for (int i = 0; i < len / 2; i++) {
        if (word[i] != word[len - 1 - i]) return 0;
    }
    return 1;
}

int main(int argc, char *argv[]) {
    if (argc != 3) {
        return 1;
    }
    int col = atoi(argv[1]);
    FILE *f = fopen(argv[2], "r");
    if (!f) return 1;

    char buffer[128];
    while (fgets(buffer, sizeof(buffer), f)) {
        char copy[128];
        strcpy(copy, buffer);

        copy[strcspn(copy, "\n")] = 0;

        char *word = strtok(copy, " \t");
        int curr = 1;
        while (word != NULL) {
            if (curr == col) {
                if (is_palindrome(word)) {
                    printf("%s", buffer);
                }
                break;
            }
            word = strtok(NULL, " \t");
            curr++;
        }
    }
    fclose(f);
    return 0;
}
EOF

    gcc -fno-stack-protector -O0 /app/legacy_filter.c -o /app/legacy_filter
    strip /app/legacy_filter
    chmod 644 /app/legacy_filter
    rm /app/legacy_filter.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
