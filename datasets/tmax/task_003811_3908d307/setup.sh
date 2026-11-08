#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    # Install PyTorch CPU to save time and space, then other packages
    pip3 install torch --index-url https://download.pytorch.org/whl/cpu
    pip3 install pandas numpy scikit-learn sentence-transformers

    mkdir -p /app
    cat << 'EOF' > /app/scorer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if(argc != 3) {
        printf("Usage: %s <input.csv> <output.csv>\n", argv[0]);
        return 1;
    }
    FILE *fin = fopen(argv[1], "r");
    FILE *fout = fopen(argv[2], "w");
    if(!fin || !fout) return 1;

    srand(42);
    double W[384];
    for(int i=0; i<384; i++) {
        double u1 = (rand() + 1.0) / (RAND_MAX + 2.0);
        double u2 = (rand() + 1.0) / (RAND_MAX + 2.0);
        double z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * M_PI * u2);
        W[i] = z0 * sqrt(0.1);
    }
    double b = 0.5;

    char line[65536];
    while(fgets(line, sizeof(line), fin)) {
        double dot = 0.0;
        char *tok = strtok(line, ",\n");
        int i = 0;
        while(tok && i < 384) {
            dot += atof(tok) * W[i];
            tok = strtok(NULL, ",\n");
            i++;
        }
        double score = 1.0 / (1.0 + exp(-(dot + b)));
        fprintf(fout, "%f\n", score);
    }
    fclose(fin);
    fclose(fout);
    return 0;
}
EOF
    gcc -O3 /app/scorer.c -o /app/legacy_scorer -lm
    rm /app/scorer.c
    chmod +x /app/legacy_scorer

    cat << 'EOF' > /setup.py
import os
import numpy as np
import pandas as pd
from sentence_transformers import SentenceTransformer

os.makedirs('/home/user', exist_ok=True)
os.makedirs('/test', exist_ok=True)

np.random.seed(42)
texts = [
    "The quick brown fox jumps over the lazy dog.",
    "Data science is an interdisciplinary field.",
    "Machine learning models require good data.",
    " ",
    np.nan,
    "Anomalous text that makes no sense blarg.",
    "I love writing Python code for automation.",
    "System architectures are evolving rapidly."
] * 125

df = pd.DataFrame({"id": range(len(texts)), "text": texts})
df.to_csv('/home/user/raw_data.csv', index=False)

test_texts = [
    "Testing the model with unseen data.",
    "Another random sentence for validation.",
    "Artificial intelligence is transforming industries."
] * 100
df_test = pd.DataFrame({"id": range(len(test_texts)), "text": test_texts})
df_test.to_csv('/test/hidden_texts.csv', index=False)

print("Downloading model and generating embeddings...")
model = SentenceTransformer('sentence-transformers/all-MiniLM-L6-v2')
embeddings = model.encode(df_test['text'].tolist())

pd.DataFrame(embeddings).to_csv('/test/test_embeddings.csv', index=False, header=False)

os.system('/app/legacy_scorer /test/test_embeddings.csv /test/test_scores.csv')

scores = pd.read_csv('/test/test_scores.csv', header=None, names=['score'])
df_truth = pd.DataFrame({'id': df_test['id'], 'score': scores['score']})
df_truth.to_csv('/test/ground_truth.csv', index=False)
EOF

    python3 /setup.py
    rm /setup.py /test/test_embeddings.csv /test/test_scores.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /test
