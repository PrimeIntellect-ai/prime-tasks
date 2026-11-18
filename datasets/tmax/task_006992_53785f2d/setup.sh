#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make
pip3 install pytest scipy

useradd -m -s /bin/bash user || true

mkdir -p /home/user/bio_project/src
mkdir -p /home/user/bio_project/data

cat << 'EOF' > /home/user/bio_project/src/gc_calc.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    char line[1024];
    int gc = 0, total = 0;
    while (fgets(line, sizeof(line), f)) {
        if (line[0] == '>') continue;
        for (int i=0; line[i]!='\n' && line[i]!='\0'; i++) {
            if (line[i]=='G' || line[i]=='C' || line[i]=='g' || line[i]=='c') gc++;
            if (line[i]=='G' || line[i]=='C' || line[i]=='A' || line[i]=='T' || 
                line[i]=='g' || line[i]=='c' || line[i]=='a' || line[i]=='t') total++;
        }
    }
    fclose(f);
    if (total == 0) return 0;
    printf("%.4f\n", (double)gc / total * 100.0);
    return 0;
}
EOF

cat << 'EOF' > /home/user/bio_project/src/Makefile
all:
	gcc -O2 gc_calc.c -o gc_calc
EOF

cat << 'EOF' > /tmp/setup_data.py
import json
import os

case_gcs = [45, 46, 44, 45, 47, 44, 46, 45, 47, 45]
control_gcs = [43, 42, 44, 43, 41, 43, 42, 44, 43, 42]

def make_seq(gc_pct, length=100):
    gc_count = int(length * gc_pct / 100)
    at_count = length - gc_count
    return "GC" * (gc_count // 2) + ("G" if gc_count % 2 else "") + "AT" * (at_count // 2) + ("A" if at_count % 2 else "")

golden = {}

for i, gc in enumerate(case_gcs):
    fname = f"case_{i+1}.fasta"
    with open(f"/home/user/bio_project/data/{fname}", "w") as f:
        f.write(f">case_{i+1}\n{make_seq(gc)}\n")
    golden[fname] = float(gc)

for i, gc in enumerate(control_gcs):
    fname = f"control_{i+1}.fasta"
    with open(f"/home/user/bio_project/data/{fname}", "w") as f:
        f.write(f">control_{i+1}\n{make_seq(gc)}\n")
    golden[fname] = float(gc)

with open("/home/user/bio_project/data/golden_gc.json", "w") as f:
    json.dump(golden, f, indent=2)
EOF

python3 /tmp/setup_data.py

chown -R user:user /home/user/bio_project
chmod -R 777 /home/user
