#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy scipy

    mkdir -p /home/user/src /home/user/data /home/user/bin

    cat << 'EOF' > /home/user/src/seq_processor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    char line[1024];
    printf("time,marker_freq\n");
    while (fgets(line, sizeof(line), f)) {
        double time;
        char seq[512];
        if (sscanf(line, "%lf,%s", &time, seq) == 2) {
            int len = strlen(seq);
            int count = 0;
            for(int i=0; i<len; i++) {
                if(seq[i] == 'G' || seq[i] == 'C') count++;
            }
            printf("%.1f,%.4f\n", time, (double)count/len);
        }
    }
    fclose(f);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/data/sequences.txt
0.0,GCGCATATGCGCATATGCGCATATGCGCATATGCGCATAT
1.0,GCGCGCATATGCGCATATGCGCATATGCGCATATGCGCAT
2.0,GCGCGCGCATATGCGCATATGCGCATATGCGCATATGCGC
3.0,GCGCGCGCGCATATGCGCATATGCGCATATGCGCATATGC
4.0,GCGCGCGCGCGCATATGCGCATATGCGCATATGCGCATAT
5.0,GCGCGCGCGCGCGCATATGCGCATATGCGCATATGCGCAT
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
