#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc strace ltrace binutils
pip3 install pytest

mkdir -p /app/bin

cat << 'EOF' > /tmp/query_formatter.c
#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include <stdlib.h>

void process_line(char *line) {
    size_t len = strlen(line);
    if (len > 0 && line[len-1] == '\n') {
        line[len-1] = '\0';
    }
    if (strlen(line) == 0) {
        printf("\n");
        return;
    }

    char *fields[1000];
    int count = 0;

    char *start = line;
    char *p = line;
    while (*p) {
        if (*p == '|') {
            *p = '\0';
            fields[count++] = start;
            start = p + 1;
        }
        p++;
    }
    fields[count++] = start;

    for (int i = 0; fields[count - 1][i]; i++) {
        fields[count - 1][i] = toupper((unsigned char)fields[count - 1][i]);
    }

    for (int i = count - 1; i >= 0; i--) {
        printf("%s", fields[i]);
        if (i > 0) printf("|");
    }
    printf("\n");
}

int main() {
    char *line = NULL;
    size_t len = 0;
    while (getline(&line, &len, stdin) != -1) {
        process_line(line);
    }
    free(line);
    return 0;
}
EOF

gcc -O2 /tmp/query_formatter.c -o /app/bin/query_formatter
strip /app/bin/query_formatter
rm /tmp/query_formatter.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
