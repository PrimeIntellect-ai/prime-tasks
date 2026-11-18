#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ build-essential
    pip3 install pytest numpy scipy pandas

    # Create directories
    mkdir -p /app
    mkdir -p /home/user/sample_clean
    mkdir -p /home/user/sample_evil
    mkdir -p /verify/clean
    mkdir -p /verify/evil

    # Create C program for sim_oracle
    cat << 'EOF' > /app/sim_oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char** argv) {
    if(argc < 3) return 1;
    FILE* fp1 = fopen(argv[1], "r");
    FILE* fp2 = fopen(argv[2], "r");
    if(!fp1 || !fp2) {
        if(fp1) fclose(fp1);
        if(fp2) fclose(fp2);
        return 1;
    }

    double f1[1000], f2[1000];
    int c1=0, c2=0;
    char buf[1024];
    while(fscanf(fp1, "%1023s", buf) == 1) {
        char clean[256];
        int idx=0;
        for(int i=0; buf[i]; i++) {
            if((buf[i]>='0' && buf[i]<='9') || buf[i]=='.' || buf[i]=='-') {
                clean[idx++] = buf[i];
            }
        }
        clean[idx]=0;
        if(idx>0) f1[c1++] = atof(clean);
    }
    while(fscanf(fp2, "%1023s", buf) == 1) {
        char clean[256];
        int idx=0;
        for(int i=0; buf[i]; i++) {
            if((buf[i]>='0' && buf[i]<='9') || buf[i]=='.' || buf[i]=='-') {
                clean[idx++] = buf[i];
            }
        }
        clean[idx]=0;
        if(idx>0) f2[c2++] = atof(clean);
    }
    fclose(fp1);
    fclose(fp2);

    double dist = 0;
    int n = c1 < c2 ? c1 : c2;
    for(int i=0; i<n; i++) {
        dist += (f1[i]-f2[i])*(f1[i]-f2[i]);
    }
    dist = sqrt(dist);
    printf("Similarity: %f\n", 1.0 / (1.0 + dist));
    return 0;
}
EOF

    gcc -O3 -o /app/sim_oracle /app/sim_oracle.c -lm
    strip /app/sim_oracle
    rm /app/sim_oracle.c

    # Create data generation script
    cat << 'EOF' > /tmp/gen_data.py
import os
import json
import numpy as np

np.random.seed(42)

def make_profile(path, mean, std, n=10):
    features = np.random.normal(mean, std, n).tolist()
    with open(path, 'w') as f:
        json.dump({"features": features}, f)

with open("/home/user/reference.json", 'w') as f:
    json.dump({"features": [0.0]*10}, f)

for i in range(50):
    make_profile(f"/home/user/sample_clean/clean_{i}.json", 0, 1)
    make_profile(f"/home/user/sample_evil/evil_{i}.json", 2.5, 1.5)

for i in range(500):
    make_profile(f"/verify/clean/clean_{i}.json", 0, 1)
    make_profile(f"/verify/evil/evil_{i}.json", 2.5, 1.5)
EOF

    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /verify
