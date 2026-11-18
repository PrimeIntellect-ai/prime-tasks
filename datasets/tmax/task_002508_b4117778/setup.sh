#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /home/user
    mkdir -p /app

    # Generate data.csv
    python3 -c '
import random
random.seed(42)
with open("/home/user/data.csv", "w") as f:
    for i in range(1, 1001):
        if random.random() < 0.1:
            val = -999.0
        else:
            val = random.gauss(50.0, 5.0)
            if i > 800 and random.random() < 0.05:
                val = 100.0 # extreme value for test set
        f.write(f"{i},{val:.2f}\n")
'

    # Create pipeline.c
    cat << 'EOF' > /home/user/pipeline.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    FILE *f = fopen("/home/user/data.csv", "r");
    if (!f) return 1;

    int ids[1000];
    float vals[1000];
    int count = 0;
    float sum = 0;
    int valid_count = 0;

    char line[256];
    while (fgets(line, sizeof(line), f) && count < 1000) {
        sscanf(line, "%d,%f", &ids[count], &vals[count]);
        if (vals[count] != -999.0) {
            sum += vals[count];
            valid_count++;
        }
        count++;
    }
    fclose(f);

    float mean = valid_count > 0 ? sum / valid_count : 0;

    FILE *out = fopen("/home/user/test_imputed.csv", "w");
    for (int i = 800; i < 1000; i++) {
        float val = vals[i];
        if (val == -999.0) val = mean;
        fprintf(out, "%d,%.2f\n", ids[i], val);
    }
    fclose(out);
    return 0;
}
EOF

    # Create outlier_scorer.c
    cat << 'EOF' > /app/outlier_scorer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        int id; float val;
        if (sscanf(line, "%d,%f", &id, &val) == 2) {
            float score = fabs(val - 50.0) / 20.0;
            if (score > 1.0) score = 1.0;
            printf("%.2f\n", score);
        }
    }
    fclose(f);
    return 0;
}
EOF

    # Compile and strip outlier_scorer
    gcc -O2 /app/outlier_scorer.c -o /app/outlier_scorer -lm
    strip /app/outlier_scorer
    rm /app/outlier_scorer.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
