#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc gdb

    pip3 install pytest

    mkdir -p /home/user/math_project
    cd /home/user/math_project

    git init
    git config --global user.name "Test User"
    git config --global user.email "test@example.com"

    cat << 'EOF' > data.txt
4
9
16
25
36
49
64
81
100
144
EOF

    cat << 'EOF' > build.sh
#!/bin/bash
gcc -g calculate.c -o calculate
EOF
    chmod +x build.sh

    cat << 'EOF' > run_math.sh
#!/bin/bash

./build.sh
./calculate data.txt > result.txt
EOF
    chmod +x run_math.sh

    cat << 'EOF' > calculate.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    double *results = NULL;
    int count = 0;
    double val;
    double sum = 0;

    while (fscanf(f, "%lf", &val) == 1) {
        results[count] = sqrt(val);
        sum += results[count];
        count++;
    }
    fclose(f);
    printf("Sum: %.2f\n", sum);
    return 0;
}
EOF

    git add .
    git commit -m "Initial commit with data and scripts"

    rm data.txt
    git add data.txt
    git commit -m "Oops, deleted data.txt"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
