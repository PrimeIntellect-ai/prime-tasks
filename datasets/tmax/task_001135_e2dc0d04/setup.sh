#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > dataset.csv
feature,label
12.5,0
14.2,0
NaN,0
11.1,0
13.3,0
10.5,0
15.0,0
12.1,0
14.4,0
11.9,0
13.2,0
12.8,0
NaN,0
10.9,0
14.1,0
13.5,0
11.5,0
12.2,0
14.6,0
12.9,0
22.1,1
24.5,1
21.3,1
NaN,1
23.4,1
25.1,1
22.8,1
21.9,1
24.2,1
23.1,1
22.5,1
21.1,1
24.8,1
23.7,1
22.2,1
21.6,1
25.4,1
NaN,1
23.9,1
22.7,1
13.1,0
11.8,0
14.9,0
12.4,0
10.2,0
13.8,0
11.4,0
14.7,0
12.6,0
13.9,0
23.2,1
21.5,1
24.9,1
22.4,1
25.5,1
23.8,1
21.4,1
24.7,1
22.6,1
23.3,1
11.2,0
13.6,0
12.3,0
14.8,0
10.7,0
11.6,0
13.4,0
12.7,0
14.3,0
10.8,0
24.1,1
22.9,1
21.8,1
25.2,1
23.6,1
24.4,1
21.7,1
22.3,1
25.3,1
23.5,1
14.5,0
11.3,0
12.0,0
13.7,0
10.4,0
14.0,0
11.7,0
13.0,0
10.6,0
12.0,0
21.2,1
25.0,1
23.0,1
24.6,1
22.0,1
21.0,1
24.3,1
23.4,1
25.0,1
22.1,1
EOF

    cat << 'EOF' > classifier.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void calculate_means(const char *filename, double *mean0, double *mean1) {
    FILE *f = fopen(filename, "r");
    if (!f) return;
    char line[256];
    double sum0 = 0, sum1 = 0;
    int count0 = 0, count1 = 0;

    while (fgets(line, sizeof(line), f)) {
        char *feat_str = strtok(line, ",");
        char *label_str = strtok(NULL, "\n");
        if (!feat_str || !label_str) continue;

        double feat = atof(feat_str); // BUG: "NaN" becomes 0.0
        int label = atoi(label_str);

        if (label == 0) {
            sum0 += feat;
            count0++;
        } else {
            sum1 += feat;
            count1++;
        }
    }
    fclose(f);

    *mean0 = count0 ? sum0 / count0 : 0;
    *mean1 = count1 ? sum1 / count1 : 0;
}

int main(int argc, char **argv) {
    if (argc < 3) return 1;
    double mean0, mean1;
    calculate_means(argv[1], &mean0, &mean1);

    double threshold = (mean0 + mean1) / 2.0;
    int dir = (mean1 > mean0) ? 1 : -1;

    FILE *f = fopen(argv[2], "r");
    char line[256];
    int correct = 0, total = 0;

    while (fgets(line, sizeof(line), f)) {
        char *feat_str = strtok(line, ",");
        char *label_str = strtok(NULL, "\n");
        if (!feat_str || !label_str) continue;

        double feat = atof(feat_str);
        int label = atoi(label_str);

        int pred = 0;
        if (dir == 1 && feat >= threshold) pred = 1;
        if (dir == -1 && feat <= threshold) pred = 1;

        if (pred == label) correct++;
        total++;
    }
    fclose(f);

    if (total > 0)
        printf("%f\n", (double)correct / total);
    else
        printf("0.0\n");

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
