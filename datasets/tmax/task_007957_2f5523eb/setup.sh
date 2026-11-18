#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make jq
pip3 install pytest

useradd -m -s /bin/bash user || true
mkdir -p /home/user/project

cat << 'EOF' > /home/user/project/math_utils.h
#ifndef MATH_UTILS_H
#define MATH_UTILS_H
int compute_val(int n);
#endif
EOF

cat << 'EOF' > /home/user/project/math_utils.c
#include "math_utils.h"

int compute_val(int n) {
    return (n * n + 3 * n) % 256;
}
EOF

cat << 'EOF' > /home/user/project/main.c
#include <stdio.h>
#include "math_utils.h"

int main() {
    FILE *f = fopen("sequence.json", "w");
    if (!f) return 1;
    fprintf(f, "{\n  \"sequence\": [\n");
    for(int i=1; i<=50; i++) {
        fprintf(f, "    %d%s\n", compute_val(i), (i==50)?"":",");
    }
    fprintf(f, "  ]\n}\n");
    fclose(f);
    return 0;
}
EOF

cat << 'EOF' > /home/user/project/Makefile
all: app

math_utils.o: math_utils.c
	gcc -c math_utils.c

main.o: main.c
	gcc -c main.c

app: main.o math_utils.o
	gcc -o app main.o

clean:
	rm -f *.o app sequence.json
EOF

chmod -R 777 /home/user
