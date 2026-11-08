#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk
    pip3 install pytest

    mkdir -p /home/user/sim_profiling
    cd /home/user/sim_profiling

    awk 'BEGIN {
      for(i=1; i<=100000; i++) {
        if (i == 50000) {
          print "CORRUPTED_SENSOR_READING_NULL"
        } else {
          print "0.1"
        }
      }
    }' > sensor_data.txt

    cat << 'EOF' > simulation.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    FILE *file = fopen("sensor_data.txt", "r");
    if (!file) {
        perror("Failed to open file");
        return 1;
    }

    float total_sum = 0.0f; // Bug: single precision for large accumulation
    float value;

    // Bug: if fscanf fails to match a float (e.g., text), it doesn't consume the text,
    // resulting in an infinite loop.
    while (!feof(file)) {
        if (fscanf(file, "%f", &value) == 1) {
            total_sum += value;
        } else {
            // No error handling/recovery for non-floats! It just loops infinitely.
        }
    }

    fclose(file);

    printf("Total Sum: %.4f\n", total_sum);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
