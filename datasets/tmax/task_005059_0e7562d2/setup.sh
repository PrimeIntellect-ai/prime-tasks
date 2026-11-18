#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest pandas scikit-learn numpy

    mkdir -p /app/data/raw
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Create C decoder
    cat << 'EOF' > /app/sensor_decode.c
#include <stdio.h>
#include <stdlib.h>

struct Record {
    int reading_id;
    float temp;
    float humidity;
    float pressure;
};

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <input.bin> <output.csv>\n", argv[0]);
        return 1;
    }
    FILE *fin = fopen(argv[1], "rb");
    if (!fin) return 1;
    FILE *fout = fopen(argv[2], "w");
    if (!fout) { fclose(fin); return 1; }

    fprintf(fout, "reading_id,temperature,humidity,pressure\n");
    struct Record rec;
    while (fread(&rec, sizeof(struct Record), 1, fin) == 1) {
        fprintf(fout, "%d,%f,%f,%f\n", rec.reading_id, rec.temp, rec.humidity, rec.pressure);
    }

    fclose(fin);
    fclose(fout);
    return 0;
}
EOF
    gcc -O2 /app/sensor_decode.c -o /app/sensor_decode
    strip /app/sensor_decode
    rm /app/sensor_decode.c

    # Generate data using Python
    cat << 'EOF' > /tmp/gen_data.py
import struct
import random
import csv
import os

random.seed(42)

def write_bin(path, rid, temp, hum, pres):
    with open(path, 'wb') as f:
        f.write(struct.pack('ifff', rid, temp, hum, pres))

def write_csv(path, rid, temp, hum, pres):
    with open(path, 'w') as f:
        f.write("reading_id,temperature,humidity,pressure\n")
        f.write(f"{rid},{temp},{hum},{pres}\n")

metadata = []

# Generate raw data
for i in range(1, 101):
    status = "Normal" if random.random() < 0.9 else "Warning"
    metadata.append((i, status))

    if random.random() < 0.8:
        # Valid
        temp = random.uniform(-20, 50)
        hum = random.uniform(0, 100)
        pres = random.uniform(900, 1100)
    else:
        # Corrupted
        if random.random() < 0.5:
            temp = random.uniform(-500, -300) # < -273.15
            hum = random.uniform(0, 100)
        else:
            temp = random.uniform(-20, 50)
            hum = random.uniform(-50, -1) # < 0
        pres = random.uniform(900, 1100)

    write_bin(f"/app/data/raw/{i}.bin", i, temp, hum, pres)

# Write metadata
with open('/app/data/metadata.csv', 'w') as f:
    f.write("reading_id,status\n")
    for rid, status in metadata:
        f.write(f"{rid},{status}\n")

# Generate clean corpus
for i in range(101, 151):
    temp = random.uniform(-20, 50)
    hum = random.uniform(0, 100)
    pres = random.uniform(900, 1100)
    write_csv(f"/app/corpora/clean/{i}.csv", i, temp, hum, pres)

# Generate evil corpus
for i in range(151, 201):
    if random.random() < 0.33:
        temp = random.uniform(-500, -300)
        hum = random.uniform(0, 100)
    elif random.random() < 0.5:
        temp = random.uniform(-20, 50)
        hum = random.uniform(-50, -1)
    else:
        temp = random.uniform(-20, 50)
        hum = random.uniform(101, 200)
    pres = random.uniform(900, 1100)
    write_csv(f"/app/corpora/evil/{i}.csv", i, temp, hum, pres)

EOF
    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
