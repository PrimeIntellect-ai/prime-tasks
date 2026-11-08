#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_sensor_data.csv
100,S1,10.0
102,S1,14.0
105,S1,20.0
110,S1,25.0
100,S2,5.0
104,S2,9.0
110,S2,15.0
102,S1,12.0
105,S1,20.0
104,S2,9.5
101,S2,6.0
109,S1,24.0
109,S1,23.5
EOF

    cat << 'EOF' > /home/user/verify.py
import csv
import math

s1_vals = {
    100: 10.0,
    101: 12.0,
    102: 14.0,
    103: 16.0,
    104: 18.0,
    105: 20.0,
    106: 21.0,
    107: 22.0,
    108: 23.0,
    109: 24.0,
    110: 25.0
}

s2_vals = {
    100: 5.0,
    101: 6.0,
    102: 7.166666666666667,
    103: 8.333333333333334,
    104: 9.5,
    105: 10.416666666666666,
    106: 11.333333333333334,
    107: 12.25,
    108: 13.166666666666666,
    109: 14.083333333333334,
    110: 15.0
}

dist_sq = 0.0
for t in range(100, 111):
    diff = s1_vals[t] - s2_vals[t]
    dist_sq += diff * diff

distance = math.sqrt(dist_sq)

def check_resampled():
    with open('/home/user/resampled.csv', 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        if header != ['timestamp', 'S1_value', 'S2_value']:
            return False
        for row in reader:
            t = int(row[0])
            v1 = float(row[1])
            v2 = float(row[2])
            if abs(v1 - s1_vals[t]) > 1e-3 or abs(v2 - s2_vals[t]) > 1e-3:
                return False
    return True

def check_distance():
    with open('/home/user/distance.txt', 'r') as f:
        val = float(f.read().strip())
        if abs(val - distance) > 1e-3:
            return False
    return True

if check_resampled() and check_distance():
    print("PASS")
else:
    print("FAIL")
EOF
    chmod +x /home/user/verify.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
