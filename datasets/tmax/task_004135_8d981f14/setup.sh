#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    mkdir -p /home/user/etl
    cd /home/user/etl

    cat << 'EOF' > dataset_A.txt
hello world this is a test
data engineering is fun
we are building an etl pipeline
c programming requires manual memory management
testing the reproducibility of the pipeline
EOF

    cat << 'EOF' > dataset_B.txt
another day another pipeline
machine learning models need data
calculating embeddings from text
hypothesis testing and confidence intervals
evaluating the distance to the centroid
EOF

    cat << 'EOF' > embedder.c
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <input_file>\n", argv[0]);
        return 1;
    }
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    char line[1024];
    while (fgets(line, sizeof(line), f)) {
        int counts[26] = {0};
        int total = 0;
        for (int i = 0; line[i]; i++) {
            if (isalpha(line[i])) {
                counts[tolower(line[i]) - 'a']++;
                total++;
            }
        }
        for (int i = 0; i < 26; i++) {
            printf("%f%s", total > 0 ? (float)counts[i] / total : 0.0, i == 25 ? "" : ",");
        }
        printf("\n");
    }
    fclose(f);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
