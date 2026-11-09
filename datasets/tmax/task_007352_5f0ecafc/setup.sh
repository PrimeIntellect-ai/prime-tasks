#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc strace coreutils make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_project/logs

    cat << 'EOF' > /home/user/legacy_project/math_utils.c
#include <math.h>

// BUG: Using ^ (bitwise XOR) instead of multiplication/pow for squaring
double calculate_distance(double x1, double y1, double x2, double y2) {
    // Intentionally bad C code using ^ operator for exponents
    int dx = (int)(x2 - x1);
    int dy = (int)(y2 - y1);
    return sqrt((dx ^ 2) + (dy ^ 2)); 
}
EOF

    cat << 'EOF' > /home/user/legacy_project/processor.c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>

extern double calculate_distance(double x1, double y1, double x2, double y2);

int main() {
    FILE *in = fopen("test_data.txt", "r");
    FILE *out = fopen("output.txt", "w");
    int log_fd = open("logs/proc.log", O_WRONLY | O_CREAT | O_APPEND, 0644);

    double px = 0, py = 0, cx, cy;
    char buffer[256];

    while (fscanf(in, "%lf %lf", &cx, &cy) == 2) {
        double dist = calculate_distance(px, py, cx, cy);
        fprintf(out, "Dist: %f\n", dist);
        px = cx; py = cy;

        // BOTTLENECK: fsyncing the log file on every single processed record
        snprintf(buffer, sizeof(buffer), "PROC|20231025-103000.123|Processed point\n");
        write(log_fd, buffer, strlen(buffer));
        fsync(log_fd); // The agent needs to remove this fsync or move it outside the loop
        usleep(50000); // Artificial delay to simulate the block
    }

    fclose(in);
    fclose(out);
    close(log_fd);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/legacy_project/test_data.txt
0.0 0.0
1.0 1.0
2.0 2.0
3.0 3.0
4.0 4.0
5.0 5.0
6.0 6.0
7.0 7.0
8.0 8.0
9.0 9.0
10.0 10.0
EOF

    cat << 'EOF' > /home/user/legacy_project/logs/gen.log
2023-10-25T10:30:00.000Z Generator started
2023-10-25T10:30:00.050Z Generated 10 points
EOF

    cat << 'EOF' > /home/user/legacy_project/logs/proc.log
PROC|20231025-103000.100|Processor started
EOF

    cat << 'EOF' > /home/user/legacy_project/logs/agg.log
10/25/2023 10:30:01.000 AM Aggregator started
10/25/2023 10:30:01.500 AM Aggregation complete
EOF

    chmod -R 777 /home/user
