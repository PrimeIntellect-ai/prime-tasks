#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/event_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

// Calculates a custom time offset index
// Formula: (days_since_epoch * 24 + hour + timezone_offset) % 1024
int calculate_index(int days_since_epoch, int hour, int timezone_offset) {
    int raw_calc = days_since_epoch * 24 + hour + timezone_offset;

    // The bug: in C, negative numbers modulo positive numbers yield negative results.
    // E.g., -4 % 1024 = -4. 
    int index = raw_calc % 1024;

    // Assertion based intermediate validation
    assert(index >= 0 && index < 1024);

    return index;
}

int main(int argc, char **argv) {
    if (argc != 4) {
        printf("Usage: %s <days> <hour> <tz_offset>\n", argv[0]);
        return 1;
    }
    int d = atoi(argv[1]);
    int h = atoi(argv[2]);
    int tz = atoi(argv[3]);

    int idx = calculate_index(d, h, tz);
    printf("%d\n", idx);

    return 0;
}
EOF

    chmod -R 777 /home/user
