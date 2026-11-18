#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk coreutils sed grep
    pip3 install pytest

    # Create directories
    mkdir -p /app
    mkdir -p /home/user/samples/clean
    mkdir -p /home/user/samples/evil
    mkdir -p /opt/verifier/corpora/clean
    mkdir -p /opt/verifier/corpora/evil

    # Create C program for legacy_processor
    cat << 'EOF' > /app/legacy_processor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 0;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        char *ts = strtok(line, ",");
        char *sensor = strtok(NULL, ",");
        char *reading = strtok(NULL, "\r\n");
        if (sensor) {
            for (int i=0; sensor[i]; i++) {
                if (!((sensor[i]>='A' && sensor[i]<='Z') || 
                      (sensor[i]>='a' && sensor[i]<='z') || 
                      (sensor[i]>='0' && sensor[i]<='9') || 
                      sensor[i]=='-' || sensor[i]=='_')) {
                    abort();
                }
            }
        }
        if (reading) {
            if (strlen(reading) > 8) abort();
        }
    }
    fclose(f);
    return 0;
}
EOF

    gcc -O2 /app/legacy_processor.c -o /app/legacy_processor
    strip /app/legacy_processor
    rm /app/legacy_processor.c

    # Create sample files
    cat << 'EOF' > /home/user/samples/clean/sample1.csv
100,sensorA,12.3
101,sensorA,12.4
104,sensorA,12.5
EOF

    cat << 'EOF' > /home/user/samples/evil/sample1.csv
100,sensorA,123456789
EOF

    cat << 'EOF' > /home/user/samples/evil/sample2.csv
101,sensorA&B,12.3
EOF

    # Create corpora files
    cat << 'EOF' > /opt/verifier/corpora/clean/test1.csv
200,sensor-B,45.6
203,sensor-B,45.8
EOF

    cat << 'EOF' > /opt/verifier/corpora/evil/test1.csv
200,sensor_B,1234567890
EOF

    cat << 'EOF' > /opt/verifier/corpora/evil/test2.csv
201,sensor;B,45.6
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
