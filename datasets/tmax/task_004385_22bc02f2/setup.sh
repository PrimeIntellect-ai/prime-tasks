#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 python3-pip \
        tesseract-ocr \
        imagemagick \
        golang \
        gcc \
        gsfonts \
        fonts-liberation

    pip3 install pytest

    # Create directories
    mkdir -p /app/bin /app/src /app/ci

    # Create legacy_calc C code
    cat << 'EOF' > /tmp/legacy_calc.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

const char *p;

long long expr(void);

long long num(void) {
    while (isspace(*p)) p++;
    if (*p == '(') {
        p++;
        long long res = expr();
        while (isspace(*p)) p++;
        if (*p == ')') p++;
        return res;
    }
    long long res = 0;
    while (isdigit(*p)) {
        res = res * 10 + (*p - '0');
        p++;
    }
    return res;
}

long long term(void) {
    long long res = num();
    while (1) {
        while (isspace(*p)) p++;
        if (*p == '*') {
            p++;
            res *= num();
        } else if (*p == '/') {
            p++;
            long long denom = num();
            if (denom != 0) res /= denom;
        } else {
            break;
        }
    }
    return res;
}

long long expr(void) {
    long long res = term();
    while (1) {
        while (isspace(*p)) p++;
        if (*p == '+') {
            p++;
            res += term();
        } else if (*p == '-') {
            p++;
            res -= term();
        } else {
            break;
        }
    }
    return res;
}

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    p = argv[1];
    long long result = expr();
    long long abs_res = result < 0 ? -result : result;
    long long checksum = (abs_res * 839) % 59359;
    printf("Result: %lld, Checksum: %lld\n", result, checksum);
    return 0;
}
EOF

    # Compile legacy_calc
    gcc -O2 /tmp/legacy_calc.c -o /app/bin/legacy_calc
    rm /tmp/legacy_calc.c

    # Allow ImageMagick to read/write files and use ghostscript if needed
    sed -i 's/rights="none" pattern="PDF"/rights="read|write" pattern="PDF"/g' /etc/ImageMagick-6/policy.xml || true
    sed -i 's/rights="none" pattern="LABEL"/rights="read|write" pattern="LABEL"/g' /etc/ImageMagick-6/policy.xml || true

    # Generate the specification image
    convert -background white -fill black -pointsize 24 label:"SYSTEM CONFIGURATION\n--------------------\nCHECKSUM ALGORITHM:\nMULT: 839\nMOD: 59359\nEVALUATION PARSER: v2.1" /app/spec.png

    # Set permissions
    chmod -R 777 /app

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
