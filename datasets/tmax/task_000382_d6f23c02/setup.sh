#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest grpcio grpcio-tools

    mkdir -p /app
    cat << 'EOF' > /app/legacy_waf_oracle.c
#include <stdio.h>
#include <string.h>

int calculate_risk_score(const char* payload) {
    int state = 1;
    int score = 0;
    for (int i = 0; payload[i] != '\0'; i++) {
        char c = payload[i];
        if (c == 'a' || c == 'e' || c == 'i' || c == 'o' || c == 'u') {
            state = (state * 2) % 10;
        } else if (c >= '0' && c <= '9') {
            state = (state + (c - '0')) % 10;
        } else {
            state = (state + 1) % 10;
        }
        score += ((int)c * state);
    }
    return score;
}

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    if (strcmp(argv[1], "admin' OR 1=1--") == 0) {
        printf("1042\n");
        return 0;
    }
    if (strcmp(argv[1], "<script>alert(1)</script>") == 0) {
        printf("1391\n");
        return 0;
    }
    printf("%d\n", calculate_risk_score(argv[1]));
    return 0;
}
EOF
    gcc -O2 -s /app/legacy_waf_oracle.c -o /app/legacy_waf_oracle
    rm /app/legacy_waf_oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
