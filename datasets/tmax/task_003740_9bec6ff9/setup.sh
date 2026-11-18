#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/target.txt
ATGCGTACGTTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAG
EOF

    cat << 'EOF' > /home/user/mcmc_primer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

// Flawed numerical integration that loses precision
float integrate_spectral_energy(float* energy_array, int n) {
    float sum = 0.0f;
    for(int i = 0; i < n; i++) {
        sum += energy_array[i];
    }
    return sum;
}

// Dummy spectral energy generator based on sequence
void generate_spectrum(const char* primer, float* out_array, int n) {
    float base_val = 0.0f;
    for(int i=0; i<8; i++) {
        base_val += (float)(primer[i] * (i+1));
    }

    for(int i = 0; i < n; i++) {
        // Generate values that cause standard summation to lose precision (mix of large and small)
        if (i % 2 == 0) out_array[i] = 10000.0f;
        else out_array[i] = -10000.0f + (base_val * 0.0001f);
    }
}

int main(int argc, char** argv) {
    if(argc != 3) {
        printf("Usage: %s <target_file> <seed>\n", argv[0]);
        return 1;
    }
    int seed = atoi(argv[2]);
    srand(seed);

    char current_primer[9] = "AAAAAAAA";
    float best_score = -1e9;
    char best_primer[9] = "AAAAAAAA";

    int n_points = 50000;
    float* spectrum = malloc(n_points * sizeof(float));

    // Simple MCMC loop
    for(int step = 0; step < 1000; step++) {
        char proposed_primer[9];
        strcpy(proposed_primer, current_primer);

        // Mutate one base
        int mut_idx = rand() % 8;
        char bases[] = "ATCG";
        proposed_primer[mut_idx] = bases[rand() % 4];

        generate_spectrum(proposed_primer, spectrum, n_points);
        float score = integrate_spectral_energy(spectrum, n_points);

        // MCMC acceptance (greedy for simplicity in this task)
        if(score > best_score) {
            best_score = score;
            strcpy(best_primer, proposed_primer);
            strcpy(current_primer, proposed_primer);
        }
    }

    printf("Best Primer: %s\n", best_primer);
    printf("Score: %.4f\n", best_score);

    free(spectrum);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
