#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils tar
    pip3 install pytest

    mkdir -p /app/raw_data/subdir
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Create decoder.c
    cat << 'EOF' > /app/decoder.c
#include <stdio.h>
#include <stdint.h>

#pragma pack(push, 1)
struct Record {
    uint32_t seq;
    char obs[65];
    float val;
};
#pragma pack(pop)

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    struct Record rec;
    while (fread(&rec, sizeof(struct Record), 1, f) == 1) {
        printf("[RECORD]\nSEQ:%u\nOBS:%s\nVAL:%f\n[/RECORD]\n", rec.seq, rec.obs, rec.val);
    }
    fclose(f);
    return 0;
}
EOF

    gcc -O2 /app/decoder.c -o /app/decoder.bin
    strip /app/decoder.bin
    rm /app/decoder.c

    # Create dummy .dat files using python
    python3 -c "
import struct
def write_dat(filename, seq, obs, val):
    with open(filename, 'wb') as f:
        obs_b = obs.encode('utf-8').ljust(65, b'\x00')
        f.write(struct.pack('<I65sf', seq, obs_b, val))

write_dat('/app/dummy1.dat', 1, 'observation one', 1.23)
write_dat('/app/dummy2.dat', 2, 'observation two', 4.56)
"

    cd /app
    tar -czf /app/raw_data/valid1.tar.gz dummy1.dat dummy2.dat
    chmod +x /app/raw_data/valid1.tar.gz

    tar -czf /app/raw_data/subdir/valid2.tar.gz dummy1.dat
    chmod +x /app/raw_data/subdir/valid2.tar.gz

    tar -czf /app/raw_data/distractor.tar.gz dummy2.dat
    # leave distractor.tar.gz as -x
    chmod -x /app/raw_data/distractor.tar.gz

    rm dummy1.dat dummy2.dat

    # Create clean corpus
    cat << 'EOF' > /app/corpora/clean/clean1.log
[RECORD]
SEQ:10
OBS:Valid Observation
VAL:42.420000
[/RECORD]
[RECORD]
SEQ:11
OBS:Another valid one
VAL:0.000000
[/RECORD]
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpora/evil/evil1.log
[RECORD]
SEQ:-5
OBS:Negative sequence
VAL:1.230000
[/RECORD]
[RECORD]
SEQ:12
OBS:Invalid_char!
VAL:1.230000
[/RECORD]
[RECORD]
SEQ:13
OBS:This string is way too long and definitely exceeds the sixty four character limit that was specified in the requirements
VAL:1.230000
[/RECORD]
[RECORD]
SEQ:14
OBS:Missing end record
VAL:1.230000
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
