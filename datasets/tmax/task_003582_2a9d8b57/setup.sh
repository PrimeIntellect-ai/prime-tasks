#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc valgrind libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/polynomial_eval.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <math.h>

#define MAX_LINES 1000

typedef struct {
    char* expression;
    double result;
} Task;

void* evaluate_polynomial(void* arg) {
    Task* task = (Task*)arg;
    char* expr = task->expression;

    // Format parsing: simple dummy parsing, expecting "coeff x^pow"
    double coeff, power;
    double x_val = 2.0; // Evaluate at x=2.0

    // Allocate an array for parsed terms (the source of the leak!)
    double* terms = (double*)malloc(2 * sizeof(double));

    if (sscanf(expr, "%lf x^%lf", &coeff, &power) != 2) {
        // Edge-case error: Malformed string. Returns without freeing 'terms'!
        return NULL; 
    }

    terms[0] = coeff;
    terms[1] = power;

    task->result = terms[0] * pow(x_val, terms[1]);

    free(terms);
    return NULL;
}

int main() {
    char buffer[256];
    pthread_t threads[MAX_LINES];
    Task* tasks[MAX_LINES];
    int count = 0;

    while (fgets(buffer, sizeof(buffer), stdin) && count < MAX_LINES) {
        tasks[count] = (Task*)malloc(sizeof(Task));
        tasks[count]->expression = strdup(buffer);
        pthread_create(&threads[count], NULL, evaluate_polynomial, tasks[count]);
        count++;
    }

    for (int i = 0; i < count; i++) {
        pthread_join(threads[i], NULL);
        free(tasks[i]->expression);
        free(tasks[i]);
    }

    return 0;
}
EOF

    cat << 'EOF' > /home/user/fuzz_inputs.txt
3.5 x^2.0
1.0 x^1.0
malformed_input_1
4.2 x^3.0
broken_line x^
-1.5 x^0.5
just_a_string
EOF

    chmod -R 777 /home/user
