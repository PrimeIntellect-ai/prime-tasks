#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/log_tool
    mkdir -p /home/user/logs

    # Create Makefile with a literal tab
    echo -e "parser: parser.c\n\tgcc -g -O0 -Wall parser.c -o parser" > /home/user/log_tool/Makefile

    # Create parser.c
    cat << 'EOF' > /home/user/log_tool/parser.c
#include <stdio.h>
#include <stdlib.h>
#include <dirent.h>
#include <string.h>

void process_file(const char *filepath) {
    FILE *f = fopen(filepath, "r");
    if (!f) return;
    char buffer[256];
    while (fgets(buffer, sizeof(buffer), f)) {
        buffer[strcspn(buffer, "\n")] = 0;
        if (strncmp(buffer, "EVENT:", 6) == 0) {
            char *data = buffer + 6;
            char *space = strchr(data, ' ');
            // BUG: Dereferencing space without checking if it's NULL
            *space = '\0'; 
            printf("File: %s, Type: %s, Msg: %s\n", filepath, data, space + 1);
        }
    }
    fclose(f);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        printf("Usage: %s <dir>\n", argv[0]);
        return 1;
    }
    DIR *d;
    struct dirent *dir;
    d = opendir(argv[1]);
    if (d) {
        while ((dir = readdir(d)) != NULL) {
            if (strstr(dir->d_name, ".log")) {
                char path[512];
                snprintf(path, sizeof(path), "%s/%s", argv[1], dir->d_name);
                process_file(path);
            }
        }
        closedir(d);
    }
    return 0;
}
EOF

    # Create log files
    cat << 'EOF' > /home/user/logs/01.log
Some standard logging line that should be ignored
EVENT:INFO System started successfully
EVENT:WARN CPU temperature high
EOF

    cat << 'EOF' > /home/user/logs/02.log
EVENT:ERROR Disk full on /dev/sda1
EVENT:REBOOT
EVENT:INFO Recovery initiated
EOF

    cat << 'EOF' > /home/user/logs/03.log
EVENT:FATAL Kernel panic
EOF

    chmod -R 777 /home/user
