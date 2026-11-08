#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils
pip3 install pytest

# Create user
useradd -m -s /bin/bash user || true

# Setup decoder binary
mkdir -p /app
cat << 'EOF' > /app/sensor_decode.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    char *hex = argv[1];
    size_t len = strlen(hex);
    for (size_t i = 0; i < len; i += 2) {
        unsigned int val;
        sscanf(&hex[i], "%2x", &val);
        putchar(val);
    }
    putchar('\n');
    return 0;
}
EOF

gcc /app/sensor_decode.c -o /app/sensor_decode
strip /app/sensor_decode
rm /app/sensor_decode.c

# Setup historical data
mkdir -p /home/user/data
cat << 'EOF' > /tmp/generate_data.py
import random

start_time = 1715505300 - 3600
end_time = 1715505300

random.seed(42)

with open("/home/user/data/historical_context.csv", "w") as f:
    f.write("timestamp,sensor_id,value\n")
    for t in range(start_time, end_time):
        if random.random() < 0.1:
            val_str = ""
        else:
            val_str = f"{40.0 + random.random():.2f}"
        f.write(f"{t},s1,{val_str}\n")
EOF

python3 /tmp/generate_data.py
rm /tmp/generate_data.py

chmod -R 777 /home/user
