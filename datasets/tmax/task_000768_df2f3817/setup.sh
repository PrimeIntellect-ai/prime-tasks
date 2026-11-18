#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb ffmpeg tesseract-ocr
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Generate the video
    ffmpeg -f lavfi -i "color=c=black:s=800x600:d=5" -vf "drawtext=text='Kernel Panic Code\: 0x8BADF00D':fontcolor=white:fontsize=24:x=50:y=50" -c:v libx264 /app/console_panic.mp4

    # Create oracle source code
    cat << 'EOF' > /app/oracle_log_parser.c
#include <stdio.h>
#include <string.h>

int main() {
    char line[4096];
    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\r\n")] = 0;
        if (line[0] != '[') {
            printf("INVALID\n");
            continue;
        }
        char *end_bracket = strchr(line, ']');
        if (!end_bracket) {
            printf("INVALID\n");
            continue;
        }
        if (end_bracket[1] != ' ') {
            printf("INVALID\n");
            continue;
        }
        char *level_start = end_bracket + 2;
        char *colon = strchr(level_start, ':');
        if (!colon) {
            printf("INVALID\n");
            continue;
        }
        if (colon[1] != ' ') {
            printf("INVALID\n");
            continue;
        }
        *colon = '\0';
        printf("Parsed: %s | %s\n", level_start, colon + 2);
    }
    return 0;
}
EOF

    # Compile the oracle
    gcc -O2 /app/oracle_log_parser.c -o /app/oracle_log_parser
    chmod +x /app/oracle_log_parser

    # Create buggy log parser
    cat << 'EOF' > /home/user/log_parser.c
#include <stdio.h>
#include <string.h>

void parse_line(char *line) {
    char timestamp[50];
    char level[50];
    char message[1024];

    // Buggy: sscanf without limits, overflows buffers on missing ']' or long lines
    int ret = sscanf(line, "[%[^]]] %[^:]: %[^\n]", timestamp, level, message);
    if (ret == 3) {
        printf("Parsed: %s | %s\n", level, message);
    } else {
        printf("INVALID\n");
    }
}

int main() {
    char line[4096];
    while (fgets(line, sizeof(line), stdin)) {
        parse_line(line);
    }
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
