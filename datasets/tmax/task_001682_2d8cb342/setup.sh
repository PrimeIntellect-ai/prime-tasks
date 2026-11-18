#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb libc-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/log_processor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void process_line(char *line, int line_num, int *valid_count) {
    char buffer[256];
    strncpy(buffer, line, 255);
    buffer[255] = '\0';

    // Log format: TIMESTAMP|LEVEL|MESSAGE
    char *timestamp = strtok(buffer, "|");
    char *level = strtok(NULL, "|");
    char *message = strtok(NULL, "|");

    // The Bug: If message is NULL (due to missing delimiters in corrupted input),
    // strlen(message) will cause a segmentation fault.
    if (strlen(message) > 0) {
        (*valid_count)++;
    }
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <log_file>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "r");
    if (!f) {
        perror("Failed to open file");
        return 1;
    }

    char line[256];
    int line_num = 1;
    int valid_count = 0;

    while (fgets(line, sizeof(line), f)) {
        process_line(line, line_num, &valid_count);
        line_num++;
    }

    fclose(f);
    printf("SUCCESS_TOKEN: parsed_%d_valid_lines\n", valid_count);
    return 0;
}
EOF

    gcc /home/user/log_processor.c -o /home/user/log_processor

    python3 -c '
with open("/home/user/app_logs.txt", "w") as f:
    for i in range(1, 10001):
        if i == 6834:
            f.write("2023-10-24T10:00:00Z|ERROR\n") # Missing the final | and message
        else:
            f.write(f"2023-10-24T10:00:00Z|INFO|Routine log message number {i}\n")
'

    chmod -R 777 /home/user
