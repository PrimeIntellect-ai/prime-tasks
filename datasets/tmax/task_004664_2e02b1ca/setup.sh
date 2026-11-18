#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip build-essential
pip3 install pytest

mkdir -p /app /home/user/samples /var/test_corpus/clean /var/test_corpus/evil

# Compile legacy_ts_parser
cat << 'EOF' > /tmp/legacy_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    int c;
    while ((c = fgetc(f)) != EOF) {
        if (c == 0 || (c > 0 && c < 0x20 && c != '\t' && c != '\n' && c != '\r')) {
            raise(SIGSEGV);
        }
        if (c == 0xC3) {
            int next = fgetc(f);
            if (next == EOF) break;
            if ((next & 0xC0) != 0x80) raise(SIGSEGV);
        }
    }
    fclose(f);
    printf("Extracted 10 features.\n");
    return 0;
}
EOF

gcc -O2 /tmp/legacy_parser.c -o /app/legacy_ts_parser
strip /app/legacy_ts_parser
rm /tmp/legacy_parser.c

# Generate data
python3 -c '
import os

clean_dir = "/var/test_corpus/clean"
evil_dir = "/var/test_corpus/evil"
samples_dir = "/home/user/samples"

clean_data = b"timestamp,sensor_name,value\n2023-10-01T12:00:00Z,TempSensor_A,25.4\n"
for i in range(10):
    with open(f"{clean_dir}/clean_{i}.csv", "wb") as f:
        f.write(clean_data)
    if i < 3:
        with open(f"{samples_dir}/clean_{i}.csv", "wb") as f:
            f.write(clean_data)

evil_data_1 = b"timestamp,sensor_name,value\n2023-10-01T12:00:00Z,Temp\x00Sensor,25.4\n"
evil_data_2 = b"timestamp,sensor_name,value\n2023-10-01T12:00:00Z,Temp\xc3\x28Sensor,25.4\n"
evil_data_3 = b"timestamp,sensor_name,value\n2023-10-01T12:00:00Z,Temp\x07Sensor,25.4\n"

evils = [evil_data_1, evil_data_2, evil_data_3] * 4

for i, data in enumerate(evils):
    with open(f"{evil_dir}/evil_{i}.csv", "wb") as f:
        f.write(data)
    if i < 3:
        with open(f"{samples_dir}/evil_{i}.csv", "wb") as f:
            f.write(data)
'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /var/test_corpus
