#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make cmake gcc
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if(argc != 6) return 1;
    double t1 = atof(argv[1]);
    double v1 = atof(argv[2]);
    double t2 = atof(argv[3]);
    double v2 = atof(argv[4]);
    double t_target = atof(argv[5]);

    double t_norm = (t_target - t1) / (t2 - t1);
    // Proprietary ease-in curve
    double val = v1 + (v2 - v1) * (t_norm * t_norm);

    printf("%.4f\n", val);
    return 0;
}
EOF
    gcc -O2 -s -o /app/interp_oracle /app/oracle.c
    rm /app/oracle.c

    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    cat << 'EOF' > /home/user/corpora/clean/test1.csv
Timestamp,SensorID,SensorDescription,Value,IsInterpolated
1600000000,TMP-1024-A1B2,Valid UTF8 Description ❤️,10.0,0
1600000005,TMP-1024-A1B2,Valid UTF8 Description ❤️,12.5,1
1600000010,TMP-1024-A1B2,Valid UTF8 Description ❤️,20.0,0
EOF

    cat << 'EOF' > /home/user/corpora/evil/test_regex.csv
Timestamp,SensorID,SensorDescription,Value,IsInterpolated
1600000000,tmp-1024-a1b2,Valid UTF8,10.0,0
EOF

    printf "Timestamp,SensorID,SensorDescription,Value,IsInterpolated\n1600000000,TMP-1024-A1B2,Invalid byte \xff here,10.0,0\n" > /home/user/corpora/evil/test_encoding.csv

    cat << 'EOF' > /home/user/corpora/evil/test_math.csv
Timestamp,SensorID,SensorDescription,Value,IsInterpolated
1600000000,TMP-1024-A1B2,Valid UTF8 Description,10.0,0
1600000005,TMP-1024-A1B2,Valid UTF8 Description,15.0,1
1600000010,TMP-1024-A1B2,Valid UTF8 Description,20.0,0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
