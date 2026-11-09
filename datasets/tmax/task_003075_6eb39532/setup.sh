#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy

    mkdir -p /app
    cat << 'EOF' > /tmp/legacy_cleaner.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main() {
    char line[1024];
    if (fgets(line, sizeof(line), stdin) == NULL) return 1;

    line[strcspn(line, "\r\n")] = 0;

    char *pipe_pos = strchr(line, '|');
    if (!pipe_pos) return 1;

    *pipe_pos = '\0';
    char *text = line;
    char *vec_str = pipe_pos + 1;

    float v0, v1, v2;
    if (sscanf(vec_str, "%f,%f,%f", &v0, &v1, &v2) != 3) return 1;

    float t0 = (float)strlen(text);
    float t1 = 0.0f;
    float t2 = 0.0f;

    int in_word = 0;
    for (int i = 0; text[i] != '\0'; i++) {
        t2 += (float)text[i];
        if (text[i] != ' ') {
            if (!in_word) {
                t1 += 1.0f;
                in_word = 1;
            }
        } else {
            in_word = 0;
        }
    }

    float v_new0 = 1.5f * v0 - 0.5f * v1;
    float v_new1 = 1.0f * v1 + 2.0f * v2;
    float v_new2 = -1.0f * v0 + 1.0f * v2;

    float c0 = v_new0 + t0;
    float c1 = v_new1 + t1;
    float c2 = v_new2 + t2;

    float norm = sqrtf(c0*c0 + c1*c1 + c2*c2);
    if (norm > 0.000001f) {
        c0 /= norm;
        c1 /= norm;
        c2 /= norm;
    } else {
        c0 = 0.0f; c1 = 0.0f; c2 = 0.0f;
    }

    printf("%.6f,%.6f,%.6f\n", c0, c1, c2);
    return 0;
}
EOF

    gcc -O3 -s /tmp/legacy_cleaner.c -o /app/legacy_cleaner -lm
    rm /tmp/legacy_cleaner.c
    chmod +x /app/legacy_cleaner

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
