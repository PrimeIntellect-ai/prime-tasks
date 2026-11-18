#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        golang \
        zip \
        unzip \
        espeak \
        gcc \
        ffmpeg

    pip3 install pytest

    mkdir -p /app

    # Generate the intercepted audio file
    espeak -w /app/intercepted_comm.wav "HOTEL ECHO LIMA LIMA OSCAR WUN TREE TREE SEVEN"

    # Create the payload_encoder in C
    cat << 'EOF' > /tmp/payload_encoder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char base64_chars[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

void base64_encode(const unsigned char *in, size_t in_len, char *out) {
    size_t i = 0, j = 0;
    unsigned char char_array_3[3];
    unsigned char char_array_4[4];

    while (in_len--) {
        char_array_3[i++] = *(in++);
        if (i == 3) {
            char_array_4[0] = (char_array_3[0] & 0xfc) >> 2;
            char_array_4[1] = ((char_array_3[0] & 0x03) << 4) + ((char_array_3[1] & 0xf0) >> 4);
            char_array_4[2] = ((char_array_3[1] & 0x0f) << 2) + ((char_array_3[2] & 0xc0) >> 6);
            char_array_4[3] = char_array_3[2] & 0x3f;

            for (i = 0; (i < 4); i++)
                out[j++] = base64_chars[char_array_4[i]];
            i = 0;
        }
    }

    if (i) {
        for (size_t k = i; k < 3; k++)
            char_array_3[k] = '\0';

        char_array_4[0] = (char_array_3[0] & 0xfc) >> 2;
        char_array_4[1] = ((char_array_3[0] & 0x03) << 4) + ((char_array_3[1] & 0xf0) >> 4);
        char_array_4[2] = ((char_array_3[1] & 0x0f) << 2) + ((char_array_3[2] & 0xc0) >> 6);
        char_array_4[3] = char_array_3[2] & 0x3f;

        for (size_t k = 0; (k < i + 1); k++)
            out[j++] = base64_chars[char_array_4[k]];

        while ((i++ < 3))
            out[j++] = '=';
    }
    out[j] = '\0';
}

void reverse_string(char *str) {
    int n = strlen(str);
    for (int i = 0; i < n / 2; i++) {
        char temp = str[i];
        str[i] = str[n - i - 1];
        str[n - i - 1] = temp;
    }
}

int main() {
    unsigned char *input = NULL;
    size_t size = 0;
    size_t capacity = 1024;
    input = malloc(capacity);

    int c;
    while ((c = fgetc(stdin)) != EOF) {
        input[size++] = (unsigned char)c;
        if (size >= capacity) {
            capacity *= 2;
            input = realloc(input, capacity);
        }
    }

    const char *key = "G0PH3R";
    int key_len = 6;
    for (size_t i = 0; i < size; i++) {
        input[i] ^= key[i % key_len];
    }

    size_t out_len = 4 * ((size + 2) / 3) + 1;
    char *out = malloc(out_len);
    base64_encode(input, size, out);

    reverse_string(out);
    printf("%s", out);

    free(input);
    free(out);
    return 0;
}
EOF

    gcc -O2 -o /app/payload_encoder /tmp/payload_encoder.c
    cd /app
    zip -P HELLO1337 /app/evidence.zip payload_encoder
    rm /app/payload_encoder /tmp/payload_encoder.c

    mkdir -p /app/evidence
    cp /app/evidence.zip /app/evidence.zip.bak
    cd /app/evidence
    unzip -P HELLO1337 /app/evidence.zip.bak
    rm /app/evidence.zip.bak

    # We leave evidence.zip in /app for the user, but we also keep the unzipped version in /app/evidence 
    # for the verifier oracle path. The user is instructed to extract to /home/user/evidence.

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
