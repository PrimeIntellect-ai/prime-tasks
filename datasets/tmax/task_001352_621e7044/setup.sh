#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libomp-dev jq
    pip3 install pytest jupyter notebook scipy pandas numpy

    mkdir -p /home/user
    cd /home/user

    # 1. Generate a synthetic FASTA file
    cat << 'EOF' > generate_fasta.py
import random
random.seed(42)
with open('input.fasta', 'w') as f:
    for i in range(10000):
        length = random.randint(50, 200)
        seq = ''.join(random.choices(['A', 'C', 'G', 'T'], k=length))
        f.write(f'>seq_{i}\n{seq}\n')
EOF
    python3 generate_fasta.py
    rm generate_fasta.py

    # 2. Create the buggy C code
    cat << 'EOF' > score_fasta.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <omp.h>

#define MAX_SEQS 20000
#define MAX_LEN 500

char seqs[MAX_SEQS][MAX_LEN];
int num_seqs = 0;

void read_fasta(const char* filename) {
    FILE* f = fopen(filename, "r");
    if (!f) exit(1);
    char line[MAX_LEN];
    while (fgets(line, sizeof(line), f)) {
        if (line[0] == '>') continue;
        line[strcspn(line, "\n")] = 0;
        strcpy(seqs[num_seqs++], line);
    }
    fclose(f);
}

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    read_fasta(argv[1]);

    double global_score = 0.0;

    #pragma omp parallel for
    for (int i = 0; i < num_seqs; i++) {
        double gc_count = 0;
        int len = strlen(seqs[i]);
        for (int j = 0; j < len; j++) {
            if (seqs[i][j] == 'G' || seqs[i][j] == 'C') {
                gc_count += 1.0;
            }
        }
        double score = (gc_count / len) * 1.337 + (len * 0.001);

        #pragma omp atomic
        global_score += score;
    }

    printf("%.10f\n", global_score);
    return 0;
}
EOF

    # 3. Compile and generate baseline results
    cat << 'EOF' > generate_baseline.py
import random
random.seed(123)
base_score = 6389.2341567890
with open('baseline_results.txt', 'w') as f:
    for _ in range(50):
        jitter = random.uniform(-0.000005, 0.000005)
        f.write(f"{base_score + jitter:.10f}\n")
EOF
    python3 generate_baseline.py
    rm generate_baseline.py

    chmod 644 /home/user/score_fasta.c
    chmod 644 /home/user/input.fasta
    chmod 644 /home/user/baseline_results.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
