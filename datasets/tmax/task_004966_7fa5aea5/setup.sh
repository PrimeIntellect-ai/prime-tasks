#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest pandas

    mkdir -p /app/data/snapshots /app/bin /app/corpus/evil /app/corpus/clean

    # Generate the stripped binary
    cat << 'EOF' > /tmp/eval_metric.c
#include <stdio.h>
#include <ctype.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if(argc != 2) return 1;
    int upper = 0;
    int total = 0;
    for(int i=0; i<strlen(argv[1]); i++) {
        if(isalpha(argv[1][i])) {
            total++;
            if(isupper(argv[1][i])) upper++;
        }
    }
    if(total == 0) printf("0.0\n");
    else printf("%f\n", (float)upper / total);
    return 0;
}
EOF
    gcc -O2 /tmp/eval_metric.c -o /app/bin/eval_metric
    strip /app/bin/eval_metric

    # Generate initial snapshot data
    cat << 'EOF' > /app/data/snapshots/2023-10-01.csv
date,msg_id,en_US,fr_FR,es_ES,de_DE
2023-10-01,greeting,Hello,Bonjour,Hola,Hallo
2023-10-01,farewell,Goodbye,Au revoir,Adios,Tschuss
EOF

    cat << 'EOF' > /app/data/snapshots/2023-10-02.csv
date,msg_id,en_US,fr_FR,es_ES,de_DE
2023-10-02,greeting,Hello,Bonjour,CLICK HERE TO WIN,Hallo
2023-10-02,farewell,Goodbye,Au revoir,Adios,Tschuss
EOF

    # Generate corpora for verifier
    cp /app/data/snapshots/2023-10-02.csv /app/corpus/evil/test_evil.csv
    cp /app/data/snapshots/2023-10-01.csv /app/corpus/clean/test_clean.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
