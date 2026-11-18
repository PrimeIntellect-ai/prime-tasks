#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils bc gawk
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    int cat = 0, dog = 0, bird = 0, fish = 0;
    char word[256];
    while (fscanf(f, "%255s", word) == 1) {
        char clean[256];
        int j = 0;
        for(int i=0; word[i]; i++) {
            if (word[i] != '.' && word[i] != ',' && word[i] != '!' && word[i] != '?') {
                clean[j++] = tolower((unsigned char)word[i]);
            }
        }
        clean[j] = '\0';

        if (strcmp(clean, "cat") == 0) cat++;
        else if (strcmp(clean, "dog") == 0) dog++;
        else if (strcmp(clean, "bird") == 0) bird++;
        else if (strcmp(clean, "fish") == 0) fish++;
    }
    fclose(f);

    float score = 2.5 * cat + 1.2 * dog - 0.8 * bird + 0.5 * fish + 1.0;
    printf("%.2f\n", score);
    return 0;
}
EOF

    gcc -O2 /tmp/oracle.c -o /app/score_oracle
    strip /app/score_oracle
    rm /tmp/oracle.c

    cat << 'EOF' > /tmp/verifier.py
import os
import subprocess
import random
import string

def generate_text():
    words = ["cat", "dog", "bird", "fish", "apple", "tree", "car", "house", "Cat!", "DOG.", "bIrD?"]
    return " ".join(random.choices(words, k=50))

mse = 0.0
n = 20
for i in range(n):
    with open(f"/tmp/test_{i}.txt", "w") as f:
        f.write(generate_text())

    oracle_out = subprocess.check_output(["/app/score_oracle", f"/tmp/test_{i}.txt"]).decode().strip()
    agent_out = subprocess.check_output(["bash", "/home/user/score.sh", f"/tmp/test_{i}.txt"]).decode().strip()

    diff = float(oracle_out) - float(agent_out)
    mse += diff * diff

mse /= n
print(mse)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
