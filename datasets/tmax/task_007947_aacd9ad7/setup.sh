#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    mkdir -p /home/user/data /home/user/src /home/user/output

    cat << 'EOF' > /home/user/data/sensors.csv
1,1620000000,10.5
2,1620000005,22.1
3,1620000010,15.0
1,1620000015,11.2
EOF

    cat << 'EOF' > /home/user/data/calibration.csv
1,-0.5,1.2
2,1.1,0.9
3,0.0,1.0
EOF

    cat << 'EOF' > /home/user/src/clean_join.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_SENSORS 100

typedef struct {
    int id;
    double offset;
    double multiplier;
} Calibration;

int main(int argc, char *argv[]) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <sensors.csv> <calibration.csv>\n", argv[0]);
        return 1;
    }

    FILE *f_sens = fopen(argv[1], "r");
    FILE *f_cal = fopen(argv[2], "r");

    if (!f_sens || !f_cal) {
        fprintf(stderr, "Error opening files.\n");
        return 1;
    }

    Calibration cal_data[MAX_SENSORS];
    int cal_count = 0;

    // Read calibration data
    int c_id;
    double c_off, c_mult;
    // Bug here: %f used for double
    while (fscanf(f_cal, "%d,%f,%f", &c_id, &c_off, &c_mult) == 3) {
        cal_data[cal_count].id = c_id;
        cal_data[cal_count].offset = c_off;
        cal_data[cal_count].multiplier = c_mult;
        cal_count++;
    }
    fclose(f_cal);

    // Process sensor data
    int s_id;
    char timestamp[64];
    double s_val;

    // Bug here: %f used for double
    while (fscanf(f_sens, "%d,%[^,],%f", &s_id, timestamp, &s_val) == 3) {
        double offset = 0.0;
        double mult = 1.0;
        for (int i = 0; i < cal_count; i++) {
            if (cal_data[i].id == s_id) {
                offset = cal_data[i].offset;
                mult = cal_data[i].multiplier;
                break;
            }
        }
        double cleaned = (s_val + offset) * mult;
        printf("%d,%s,%.2f\n", s_id, timestamp, cleaned);
    }

    fclose(f_sens);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
