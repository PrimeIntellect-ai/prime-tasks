#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make binutils
    pip3 install pytest

    # Create app directory
    mkdir -p /app

    # Create legacy binary source
    cat << 'EOF' > /tmp/legacy.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main() {
    double x;
    while (scanf("%lf", &x) == 1) {
        double c = x;
        int sign = 1;
        if (c < 0) {
            sign = -1;
            c = -c;
        }
        double guess = c;
        if (guess == 0.0) {
            printf("%.6f ", 0.0);
            continue;
        }
        for (int i = 0; i < 1000; i++) {
            double next = guess - (guess*guess*guess - c) / (3*guess*guess);
            if (fabs(next - guess) < 1e-9) {
                guess = next;
                break;
            }
            guess = next;
        }
        printf("%.6f ", sign * guess);
    }
    return 0;
}
EOF

    # Compile and strip legacy binary
    gcc -O3 /tmp/legacy.c -lm -o /app/legacy_transform
    strip /app/legacy_transform
    rm /tmp/legacy.c

    # Create conflicting header
    mkdir -p /usr/local/include/math_utils
    cat << 'EOF' > /usr/local/include/math_utils/special.h
#ifndef SPECIAL_H
#define SPECIAL_H
#include <math.h>
// Conflicting macro definition
#define fabs(x) ((x) > 0 ? (x) : -(x))
#endif
EOF

    # Create user and home directory
    useradd -m -s /bin/bash user || true

    # Create buggy source code
    cat << 'EOF' > /home/user/new_transform.c
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <math_utils/special.h>

#define MAX_VALS 100000

double inputs[MAX_VALS];
double outputs[MAX_VALS];
int num_vals = 0;
int current_index = 0; // Shared index without protection

void* process(void* arg) {
    while (1) {
        int i = current_index; // Race condition
        current_index++;
        if (i >= num_vals) break;

        double c = inputs[i];
        double guess = c;

        // Convergence bug: doesn't handle negative numbers properly
        if (guess == 0.0) {
            outputs[i] = 0.0;
            continue;
        }

        for (int j = 0; j < 1000; j++) {
            double next = guess - (guess*guess*guess - c) / (3*guess*guess);
            if (fabs(next - guess) < 1e-9) {
                guess = next;
                break;
            }
            guess = next;
        }
        outputs[i] = guess;
    }
    return NULL;
}

int main() {
    double x;
    while (scanf("%lf", &x) == 1) {
        inputs[num_vals++] = x;
    }

    pthread_t threads[4];
    for (int i = 0; i < 4; i++) {
        pthread_create(&threads[i], NULL, process, NULL);
    }
    for (int i = 0; i < 4; i++) {
        pthread_join(threads[i], NULL);
    }

    for (int i = 0; i < num_vals; i++) {
        printf("%.6f ", outputs[i]);
    }
    return 0;
}
EOF

    chmod -R 777 /home/user
