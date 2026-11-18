#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest flask requests

    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/workspace/scheduler.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Returns a dynamically allocated string representing scheduled start times.
// Caller is responsible for freeing the returned string.
char* solve_schedule(const char* input) {
    // BUG 1: Off-by-one error (forgot +1 for null terminator)
    char* copy = malloc(strlen(input)); 
    strcpy(copy, input);

    char* result = malloc(2048);
    result[0] = '\0';
    int current_time = 0;

    char* token = strtok(copy, ";");
    while(token != NULL) {
        // BUG 2: Buffer overflow if task name is long. "DesignSystemArchitecture" is 24 chars!
        char name[10]; 
        int duration;

        // Parse the custom format
        if (sscanf(token, "%[^,],%d", name, &duration) == 2) {
            char temp[100];
            sprintf(temp, "%s:%d;", name, current_time);
            strcat(result, temp);
            current_time += duration;
        }
        token = strtok(NULL, ";");
    }

    // BUG 3: Memory leak. 'copy' is never freed.
    return result; 
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
