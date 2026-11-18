#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/cleaner_oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_LINE 10000
#define MAX_NUMS 1000

int main() {
    char line[MAX_LINE];
    while (fgets(line, sizeof(line), stdin)) {
        int nums[MAX_NUMS];
        int count = 0;
        char *token = strtok(line, " \t\n");
        while (token && count < MAX_NUMS) {
            nums[count++] = atoi(token);
            token = strtok(NULL, " \t\n");
        }
        if (count == 0) {
            printf("\n");
            continue;
        }
        int min = nums[0], max = nums[0];
        for (int i = 1; i < count; i++) {
            if (nums[i] < min) min = nums[i];
            if (nums[i] > max) max = nums[i];
        }
        for (int i = 0; i < count; i++) {
            int scaled = 0;
            if (max > min) {
                scaled = (int)(((long long)(nums[i] - min) * 255) / (max - min));
            }
            printf("%d%s", scaled, (i == count - 1) ? "" : " ");
        }
        printf("\n");
    }
    return 0;
}
EOF
    gcc -O3 /tmp/cleaner_oracle.c -o /app/cleaner_oracle
    strip /app/cleaner_oracle
    rm /tmp/cleaner_oracle.c
    chmod +x /app/cleaner_oracle

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
