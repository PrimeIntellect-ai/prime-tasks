#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc valgrind
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_daemon.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char** argv) {
    if (argc < 2) {
        printf("Usage: %s <csv_file>\n", argv[0]);
        return 1;
    }

    FILE* f = fopen(argv[1], "r");
    if (!f) {
        perror("Failed to open input file");
        return 1;
    }

    FILE* out = fopen("/home/user/output.log", "w");
    if (!out) {
        perror("Failed to open output file");
        fclose(f);
        return 1;
    }

    char line[256];
    while (fgets(line, sizeof(line), f)) {
        // We duplicate the line to simulate string manipulation / buffering that happens in the real daemon
        char* record = strdup(line);
        if (!record) continue;

        float start_time, end_time, val;
        int parsed = sscanf(record, "%f,%f,%f", &start_time, &end_time, &val);

        if (parsed != 3) {
            // Corrupt data, skip
            continue;
        }

        if (val < 0) {
            // Invalid sensor value, skip
            continue;
        }

        // Aggregate data over small time increments (0.05 seconds)
        float current = start_time;
        float sum = 0;
        int count = 0;

        while (current < end_time) {
            sum += val;
            count++;
            current += 0.05f; // Advance window
        }

        if (count > 0) {
            fprintf(out, "Window: %f to %f, avg: %f\n", start_time, end_time, sum/count);
        }

        free(record);
    }

    fclose(f);
    fclose(out);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/data.csv
1700000000.0,1700000000.2,10.0
corrupted_string_data_here
1700000001.0,1700000001.1,20.0
1700000002.0,1700000002.05,-5.0
1700000003.0,1700000003.15,30.0
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
