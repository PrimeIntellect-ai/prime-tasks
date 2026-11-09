#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb
    pip3 install pytest

    mkdir -p /home/user/engine

    cat << 'EOF' > /home/user/engine/process.c
#include <stdio.h>
#include <stdlib.h>

void process_line(float a, float b, float c) {
    // Due to limited precision of 'float', a^2 and b^2 can become equal 
    // if a and b are very close, leading to catastrophic cancellation.
    float denom_f = (a * a) - (b * b);

    // Casting to int for legacy downstream processing.
    // If denom_f is 0.0, this becomes 0, and integer division traps SIGFPE.
    int denom = (int)denom_f;

    int result = (int)c / denom;

    // Volatile to prevent compiler optimization from removing the calculation
    volatile int keep = result;
}

int main(int argc, char** argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <input_file>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "r");
    if (!f) {
        perror("Failed to open file");
        return 1;
    }

    float a, b, c;
    int line = 0;
    while (fscanf(f, "%f %f %f", &a, &b, &c) == 3) {
        process_line(a, b, c);
        line++;
    }

    printf("Successfully processed %d lines\n", line);
    fclose(f);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/engine/build.sh
#!/bin/bash
gcc -g -O0 /home/user/engine/process.c -o /home/user/engine/process
EOF
    chmod +x /home/user/engine/build.sh

    cat << 'EOF' > /tmp/gen_input.py
import random

random.seed(42)
with open("/home/user/engine/input.txt", "w") as f:
    for i in range(1000):
        if i == 421:
            # Poison pill: catastrophic cancellation in single precision float
            # 1000.0001^2 - 1000.0000^2 -> precision loss makes them equal in float
            f.write("1000.0001 1000.0000 500.0\n")
        else:
            # Safe values
            a = random.uniform(10.0, 50.0)
            b = random.uniform(1.0, 5.0)
            c = random.uniform(100.0, 200.0)
            f.write(f"{a:.4f} {b:.4f} {c:.4f}\n")
EOF
    python3 /tmp/gen_input.py
    rm /tmp/gen_input.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
