#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk
    pip3 install pytest

    mkdir -p /home/user

    # Generate embeddings.csv
    awk 'BEGIN {
      srand(42);
      for(i=1; i<=1000; i++) {
        printf "%.4f,%.4f,%.4f,%.4f,%.4f\n", 
          (rand()*2-1), (rand()*2-1), (rand()*2-1), (rand()*2-1), (rand()*2-1)
      }
    }' > /home/user/embeddings.csv

    # Create the broken aggregate.c
    cat << 'EOF' > /home/user/aggregate.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    FILE *fp = fopen("/home/user/embeddings.csv", "r");
    if (!fp) {
        perror("Failed to open input");
        return 1;
    }

    // BUG: sums is int, so adding floats between -1 and 1 truncates to 0!
    int sums[5] = {0}; 
    double vals[5];
    int count = 0;

    while (fscanf(fp, "%lf,%lf,%lf,%lf,%lf", &vals[0], &vals[1], &vals[2], &vals[3], &vals[4]) == 5) {
        for (int i=0; i<5; i++) {
            sums[i] += vals[i];
        }
        count++;
    }
    fclose(fp);

    FILE *out = fopen("/home/user/centroid.csv", "w");
    if (!out) return 1;

    for (int i=0; i<5; i++) {
        fprintf(out, "%.4f%s", (double)sums[i]/count, i==4 ? "" : ",");
    }
    fprintf(out, "\n");
    fclose(out);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
