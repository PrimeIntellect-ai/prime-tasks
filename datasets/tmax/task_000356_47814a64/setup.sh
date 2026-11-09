#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/uptime_monitor.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <new_latency>\n", argv[0]);
        return 1;
    }

    double new_latency = atof(argv[1]);

    FILE *f = fopen("/home/user/state.txt", "r");
    if (!f) {
        perror("Failed to open state.txt");
        return 1;
    }

    int count;
    double sum, sum_sq;
    if (fscanf(f, "%d %lf %lf", &count, &sum, &sum_sq) != 3) {
        fprintf(stderr, "Invalid state format\n");
        fclose(f);
        return 1;
    }
    fclose(f);

    // Update state
    count += 1;
    sum += new_latency;
    sum_sq += (new_latency * new_latency);

    // Naive variance calculation
    double mean = sum / count;
    double mean_of_squares = sum_sq / count;

    // THIS CAN BE NEGATIVE DUE TO PRECISION LOSS
    double variance = mean_of_squares - (mean * mean);

    // stddev = sqrt(variance), which yields NaN if variance < 0
    double stddev = sqrt(variance);

    printf("%.6f\n", stddev);

    // Save state back (omitted for brevity in this task, but normally happens here)

    return 0;
}
EOF

    chmod +x /home/user/uptime_monitor.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
