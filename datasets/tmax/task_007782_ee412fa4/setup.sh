#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/log_tool
    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/service_a.log
1620000005 Service A started
1620000010 Service A connecting
CORRUPTED_LINE_NO_SPACE_OR_TIMESTAMP
1620000020 Service A connected
EOF

    cat << 'EOF' > /home/user/logs/service_b.log
1620000001 Service B initialized
1620000008 Service B waiting
1620000015 Service B error
EOF

    cat << 'EOF' > /home/user/log_tool/aggregator.c
#include <stdio.h>
#include <string.h>
// BUG 1: Missing stdlib.h causes implicit declaration of atoi and qsort to fail with -Werror

#define MAX_LINES 100

struct LogLine {
    int timestamp;
    char message[256];
};

int compare(const void *a, const void *b) {
    return ((struct LogLine*)a)->timestamp - ((struct LogLine*)b)->timestamp;
}

int main(int argc, char *argv[]) {
    struct LogLine lines[MAX_LINES];
    int count = 0;

    for (int i = 1; i < argc; i++) {
        FILE *f = fopen(argv[i], "r");
        if (!f) continue;
        char buffer[256];
        while (fgets(buffer, sizeof(buffer), f)) {
            char *space = strchr(buffer, ' ');

            // BUG 2: Missing check for NULL space pointer causes segfault on corrupted lines

            *space = '\0';
            lines[count].timestamp = atoi(buffer);
            strcpy(lines[count].message, space + 1);
            count++;
        }
        fclose(f);
    }

    qsort(lines, count, sizeof(struct LogLine), compare);

    FILE *out = fopen("/home/user/timeline.txt", "w");
    if (!out) return 1;
    for (int i = 0; i < count; i++) {
        fprintf(out, "%d %s", lines[i].timestamp, lines[i].message);
    }
    fclose(out);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/log_tool/Makefile
CFLAGS = -Wall -Werror=implicit-function-declaration

aggregator: aggregator.c
	gcc $(CFLAGS) -o aggregator aggregator.c

clean:
	rm -f aggregator
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
