#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/src /home/user/seq_data /home/user/bin

    # Create the C program
    cat << 'EOF' > /home/user/src/score_seq.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char filepath[512];
    double total_score = 0.0;

    while (fgets(filepath, sizeof(filepath), stdin)) {
        filepath[strcspn(filepath, "\n")] = 0;
        FILE *f = fopen(filepath, "r");
        if (f) {
            double val = 0.0;
            if (fscanf(f, "%lf", &val) == 1) {
                total_score += val;
            }
            fclose(f);
        }
    }

    printf("%.15f\n", total_score);
    return 0;
}
EOF

    # Generate 50 float data files
    python3 -c '
import random
import os
random.seed(42)
os.makedirs("/home/user/seq_data", exist_ok=True)
for i in range(1, 51):
    with open(f"/home/user/seq_data/seq_{i:02d}.dat", "w") as f:
        f.write(f"{random.uniform(0.0001, 1000.0):.15f}\n")
'

    # Create the flawed pipeline script
    cat << 'EOF' > /home/user/run_pipeline.sh
#!/bin/bash
find /home/user/seq_data -type f -name "*.dat" | /home/user/bin/score_seq
EOF
    chmod +x /home/user/run_pipeline.sh

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/src /home/user/seq_data /home/user/run_pipeline.sh
    chmod -R 777 /home/user
