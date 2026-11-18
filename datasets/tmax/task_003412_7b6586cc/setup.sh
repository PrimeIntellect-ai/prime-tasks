#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libc6-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/server.log
192.168.1.1 12/Oct/2023 200 1024
10.0.0.5 2023-10-12 404 512
192.168.1.1 13/Oct/2023 200 2048
172.16.0.2 2023-10-13 500 0
EOF

    cat << 'EOF' > /home/user/log_analyzer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

typedef struct {
    char ip[32];
    int year;
    int status;
    int bytes;
} LogEntry;

void parse_date(const char* date_str, int* year) {
    char month[10];
    int day;
    // BUG 1: Only handles DD/MMM/YYYY
    if (sscanf(date_str, "%d/%3s/%d", &day, month, year) != 3) {
        *year = 0; // Fails on YYYY-MM-DD
    }
}

double calculate_score(int status, int bytes) {
    double score = 1.0;
    double old_score;
    double epsilon = 0.001;
    int iterations = 0;

    do {
        old_score = score;
        score = (score + (bytes / (double)(status + 1))) / 2.0;
        // BUG 2: Missing absolute value for convergence check
        // if old_score > score, (score - old_score) is negative and loop exits immediately
    } while ((score - old_score) > epsilon && iterations++ < 100);

    return score;
}

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <input_log> <output_file>\n", argv[0]);
        return 1;
    }

    FILE *in = fopen(argv[1], "r");
    FILE *out = fopen(argv[2], "w");
    if (!in || !out) return 1;

    char ip[32], date[32];
    int status, bytes;

    while (fscanf(in, "%31s %31s %d %d", ip, date, &status, &bytes) == 4) {
        int year;
        parse_date(date, &year);
        if (year == 0) continue; // Skips invalid dates

        double score = calculate_score(status, bytes);
        fprintf(out, "IP: %s, Score: %.3f\n", ip, score);
    }

    fclose(in);
    fclose(out);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/Makefile
all:
	gcc -O2 -o log_analyzer log_analyzer.c -lm
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
