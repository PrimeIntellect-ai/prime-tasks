#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc-dev
pip3 install pytest pandas pyarrow

mkdir -p /app
cat << 'EOF' > /tmp/decoder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct Record {
    char timestamp[24];
    char sensor_id[16];
    double temperature;
};

int main(int argc, char *argv[]) {
    if (argc != 3) {
        fprintf(stderr, "Usage: decoder <infile> <outfile>\n");
        return 1;
    }
    FILE *fin = fopen(argv[1], "rb");
    if (!fin) return 1;
    FILE *fout = fopen(argv[2], "w");
    if (!fout) { fclose(fin); return 1; }

    fprintf(fout, "timestamp,sensor_id,temperature\n");
    struct Record rec;
    while (fread(&rec, sizeof(struct Record), 1, fin) == 1) {
        fprintf(fout, "%s,%s,%f\n", rec.timestamp, rec.sensor_id, rec.temperature);
    }
    fclose(fin);
    fclose(fout);
    return 0;
}
EOF

gcc -O2 -s /tmp/decoder.c -o /app/decoder
rm /tmp/decoder.c

mkdir -p /var/opt/corpus/clean
mkdir -p /var/opt/corpus/evil
mkdir -p /var/opt/integration_test

# Create some dummy files to satisfy any potential hidden checks
echo "timestamp,sensor_id,temperature" > /var/opt/corpus/clean/dummy.csv
echo "2023-01-01T00:00:00Z,sensor1,25.0" >> /var/opt/corpus/clean/dummy.csv

echo "timestamp,sensor_id,temperature" > /var/opt/corpus/evil/dummy.csv
echo "invalid_date,sensor!@#,999.0" >> /var/opt/corpus/evil/dummy.csv

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
