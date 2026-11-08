#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip strace gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create input data
    cat << 'EOF' > /home/user/input.csv
x
1
2
3
4
5
6
7
8
9
10
11
12
13
14
15
EOF

    # Create expected sample data (y = 3x^2 + 2x + 1)
    cat << 'EOF' > /home/user/expected_sample.csv
x,y
1,6
2,17
3,34
4,57
5,86
EOF

    # Write the C source for the legacy binary
    cat << 'EOF' > /home/user/legacy.c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main() {
    FILE *token = fopen("/home/user/.calc_token", "r");
    if (!token) {
        return 1;
    }
    fclose(token);

    FILE *in = fopen("/home/user/input.csv", "r");
    FILE *out = fopen("/home/user/output.csv", "w");
    if (!in || !out) return 1;

    char buffer[256];
    // skip header
    if (fgets(buffer, sizeof(buffer), in)) {
        fprintf(out, "x,y\n");
    }

    int x;
    while (fscanf(in, "%d", &x) == 1) {
        // Linear transformation instead of quadratic
        int y = 5 * x + 1;
        fprintf(out, "%d,%d\n", x, y);
    }

    fclose(in);
    fclose(out);
    return 0;
}
EOF

    # Compile the legacy binary and clean up source
    gcc -o /home/user/legacy_bin /home/user/legacy.c
    rm /home/user/legacy.c

    chmod -R 777 /home/user
