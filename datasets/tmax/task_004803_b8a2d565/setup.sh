#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc strace
    pip3 install pytest

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/app_1.log
metric=10
metric=20
EOF

    cat << 'EOF' > /home/user/logs/app_2.log
metric=15
metric=25
EOF

    # Generate 54 'X's using python to avoid bash brace expansion issues in sh
    PAD=$(python3 -c "print('X'*54)")
    echo "${PAD}metric=100" > /home/user/logs/app_3.log
    echo "metric=30" >> /home/user/logs/app_3.log

    cat << 'EOF' > /home/user/logs/app_4.log
metric=50
EOF

    cat << 'EOF' > /home/user/log_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>

int parse_file(const char *filepath) {
    FILE *fp = fopen(filepath, "r");
    if (!fp) return 0;

    int sum = 0;
    char buf[64];
    int c;

    while (1) {
        int i = 0;
        // BUG: Off-by-one boundary condition. i <= 64 allows writing to buf[64] which is out of bounds.
        while ((c = fgetc(fp)) != EOF && c != '\n' && i <= 64) {
            buf[i++] = c;
        }

        if (i == 0 && c == EOF) break;

        // BUG: if i == 64, buf[64] = '\0' causes stack corruption.
        buf[i] = '\0';

        char *ptr = strstr(buf, "metric=");
        if (ptr) {
            sum += atoi(ptr + 7);
        }

        if (c == EOF) break;
    }

    fclose(fp);
    return sum;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <log_dir> <output_file>\n", argv[0]);
        return 1;
    }

    DIR *dir = opendir(argv[1]);
    if (!dir) {
        perror("opendir");
        return 1;
    }

    int total_sum = 0;
    struct dirent *ent;
    char filepath[512];

    while ((ent = readdir(dir)) != NULL) {
        if (strstr(ent->d_name, ".log")) {
            snprintf(filepath, sizeof(filepath), "%s/%s", argv[1], ent->d_name);
            total_sum += parse_file(filepath);
        }
    }
    closedir(dir);

    FILE *out = fopen(argv[2], "w");
    if (out) {
        fprintf(out, "%d\n", total_sum);
        fclose(out);
    }

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
