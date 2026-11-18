#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make espeak
    pip3 install pytest

    # Create directories
    mkdir -p /app
    mkdir -p /home/user/log_sanitizer/corpus/clean
    mkdir -p /home/user/log_sanitizer/corpus/evil

    # Generate voicemail audio
    espeak -w /app/voicemail.wav "Hey, it's Dave. I forgot to check in the updated Makefile. It needs the dash L M flag, -lm, to link the math library for the entropy calculation. Also, I noticed the parse_nested_brackets function goes into infinite recursion if it hits a backslash escape character without advancing the string pointer. Please fix the pointer increment and make sure it correctly rejects the evil corpus!"

    # Create source code
    cat << 'EOF' > /home/user/log_sanitizer/sanitizer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

double calculate_entropy(const char* str) {
    int counts[256] = {0};
    int len = strlen(str);
    if (len == 0) return 0.0;
    for (int i = 0; i < len; i++) {
        counts[(unsigned char)str[i]]++;
    }
    double entropy = 0.0;
    for (int i = 0; i < 256; i++) {
        if (counts[i] > 0) {
            double p = (double)counts[i] / len;
            entropy -= p * log2(p);
        }
    }
    return entropy;
}

int parse_nested_brackets(const char* ptr, int depth) {
    if (*ptr == '\0') return depth == 0 ? 0 : 1;
    if (depth > 50) return 1; // reject too deep

    if (*ptr == '\\') {
        const char* next = ptr;
        // BUG: missing pointer increment to advance past the escape character
        // next += 2;
        return parse_nested_brackets(next, depth);
    }

    if (*ptr == '[') {
        return parse_nested_brackets(ptr + 1, depth + 1);
    } else if (*ptr == ']') {
        if (depth == 0) return 1;
        return parse_nested_brackets(ptr + 1, depth - 1);
    }

    return parse_nested_brackets(ptr + 1, depth);
}

int main(int argc, char** argv) {
    if (argc < 2) {
        return 0;
    }
    FILE* f = fopen(argv[1], "r");
    if (!f) return 1;

    fseek(f, 0, SEEK_END);
    long fsize = ftell(f);
    fseek(f, 0, SEEK_SET);

    char* string = malloc(fsize + 1);
    fread(string, fsize, 1, f);
    fclose(f);
    string[fsize] = 0;

    if (calculate_entropy(string) > 7.5) {
        free(string);
        return 1;
    }

    int result = parse_nested_brackets(string, 0);
    free(string);
    return result;
}
EOF

    # Create Makefile
    cat << 'EOF' > /home/user/log_sanitizer/Makefile
CC=gcc
CFLAGS=-O2

sanitizer: sanitizer.c
	$(CC) $(CFLAGS) sanitizer.c -o sanitizer
EOF

    # Create corpus files
    echo "[info] normal log entry" > /home/user/log_sanitizer/corpus/clean/1.log
    echo "[warning] nothing to see here" > /home/user/log_sanitizer/corpus/clean/2.log
    echo "\\[\\[\\[ malicious" > /home/user/log_sanitizer/corpus/evil/1.log
    echo "[info] \\[" > /home/user/log_sanitizer/corpus/evil/2.log

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
