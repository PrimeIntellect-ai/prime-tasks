#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy scipy

    mkdir -p /home/user/src /home/user/bin /home/user/data

    cat << 'EOF' > /home/user/src/score_calc.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <file> <x>\n", argv[0]);
        return 1;
    }
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    double x = atof(argv[2]);
    char line[256];
    double total_score = 0;
    int count = 0;
    while (fscanf(f, "%255s", line) == 1) {
        int gc = 0, at = 0;
        for (int i=0; line[i]; i++) {
            if (line[i]=='G' || line[i]=='C') gc++;
            else if (line[i]=='A' || line[i]=='T') at++;
        }
        total_score += (gc * x * x + at * x);
        count++;
    }
    fclose(f);
    if (count > 0) printf("%.6f\n", total_score / count);
    return 0;
}
EOF

    python3 -c '
with open("/home/user/data/sequences.txt", "w") as f:
    for _ in range(50):
        f.write("G"*20 + "A"*30 + "\n")
    for _ in range(50):
        f.write("G"*30 + "A"*20 + "\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
