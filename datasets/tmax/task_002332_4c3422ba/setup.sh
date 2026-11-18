#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/filter_seqs.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc != 3) return 1;
    FILE *in = fopen(argv[1], "r");
    FILE *out = fopen(argv[2], "w");
    char line[256];
    char name[256];
    while (fgets(line, sizeof(line), in)) {
        if (line[0] == '>') {
            sscanf(line, ">%s", name);
        } else {
            line[strcspn(line, "\n")] = 0;
            if (strlen(line) >= 30) {
                fprintf(out, "%s,%s\n", name, line);
            }
        }
    }
    fclose(in);
    fclose(out);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/raw_sequences.fasta
>SHORT_SEQ
ACGTACGT
>TARGET_SEQ
ATTATTATTATTATTATTATTATTATTATT
>OTHER_SEQ
TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT
EOF

    chmod -R 777 /home/user
