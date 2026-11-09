#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc valgrind libc6-dev
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create the main server.c
    cat << 'EOF' > /home/user/server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Forward declaration of the processing function
void process_input(const char* input);

// Missing definition that causes a linker error:
extern void init_system();

int main() {
    init_system(); // Linker error: init_system is not defined anywhere

    char line[256];
    printf("Service ready.\n");
    while (fgets(line, sizeof(line), stdin)) {
        // Strip newline
        line[strcspn(line, "\n")] = 0;
        if (strcmp(line, "QUIT") == 0) break;
        process_input(line);
    }
    return 0;
}
EOF

    # Create the raw image containing the deleted processor.c
    cat << 'EOF' > /home/user/backup.img
[GARBAGE BINARY DATA SIMULATION]
0xDEADBEEF 0xCAFEBABE
system_log_event: segfault at 0x0
// --- BEGIN PROCESSOR.C ---
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

void init_sys() {
    printf("System initialized.\n");
}

void process_input(const char* input) {
    char* buffer = malloc(1024);
    strncpy(buffer, input, 1023);
    buffer[1023] = '\0';

    if (strncmp(buffer, "CMD:", 4) == 0) {
        int i = 4;
        while (buffer[i] != ';') {
            if (buffer[i] == '\0') {
                continue; // BUG: Infinite loop if ';' is missing
            }
            i++;
        }
        printf("Processed command: %s\n", buffer);
    } else {
        printf("Ignored: %s\n", buffer);
    }
    // BUG: missing free(buffer);
}
// --- END PROCESSOR.C ---
[MORE GARBAGE DATA]
EOF

    chmod 644 /home/user/server.c /home/user/backup.img

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
