#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git gcc
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/diag-collector
cd /home/user/diag-collector

git init
git config user.email "admin@example.com"
git config user.name "Admin"

# Commit 1: Original working code but with hardcoded secret
cat << 'EOF' > main.c
#include <stdio.h>

void process_data(float* input, int count, float* output) {
    float secret = 3.14159f; // HARDCODED SECRET
    for (int i = 0; i < count; i++) {
        output[i] = (input[i] * secret) / 7.0f;
    }
}

void serialize(float* data, int count, FILE* out) {
    for (int i = 0; i < count; i++) {
        fwrite(&data[i], sizeof(float), 1, out);
    }
}

int main() {
    float input[] = {10.5f, 20.2f, 15.0f, 8.8f, 42.0f};
    int count = 5;
    float output[5];

    process_data(input, count, output);

    FILE* out = fopen("/home/user/diagnostic_report.bin", "wb");
    serialize(output, count, out);
    fclose(out);

    return 0;
}
EOF
git add main.c
git commit -m "Initial working version of diag-collector"

# Commit 2: Broken refactor
cat << 'EOF' > main.c
#include <stdio.h>

void process_data(float* input, int count, float* output, float secret) {
    for (int i = 0; i < count; i++) {
        // Refactored formula (BUG: Precision loss via integer truncation)
        int temp = input[i] * secret;
        output[i] = temp / 7; 
    }
}

void serialize(float* data, int count, FILE* out) {
    // BUG: Off-by-one error
    for (int i = 0; i <= count; i++) { 
        fwrite(&data[i], sizeof(float), 1, out);
    }
}

int main() {
    float input[] = {10.5f, 20.2f, 15.0f, 8.8f, 42.0f};
    int count = 5;
    float output[5];

    FILE* sf = fopen("/home/user/secret.key", "r");
    if (!sf) {
        printf("Error: Missing /home/user/secret.key\n");
        return 1;
    }
    float secret;
    fscanf(sf, "%f", &secret);
    fclose(sf);

    process_data(input, count, output, secret);

    FILE* out = fopen("/home/user/diagnostic_report.bin", "wb");
    serialize(output, count, out);
    fclose(out);

    return 0;
}
EOF
git add main.c
git commit -m "Refactor: remove hardcoded secret, read from file"

chmod -R 777 /home/user
