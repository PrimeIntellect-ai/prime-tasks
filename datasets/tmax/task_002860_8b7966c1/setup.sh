#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/dataset.txt
data science data processing data mining
EOF

    cat << 'EOF' > /home/user/tokenize_bayes.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_WORDS 1000
#define MAX_WORD_LEN 100

typedef struct {
    char word[MAX_WORD_LEN];
    int count;
} WordCount;

int main() {
    FILE *in = fopen("/home/user/dataset.txt", "r");
    FILE *out = fopen("/home/user/output.csv", "w");

    if (!in || !out) {
        if(in) fclose(in);
        if(out) fclose(out);
        return 1;
    }

    char *env_alpha = getenv("BAYES_ALPHA");
    if (!env_alpha) {
        // Bug: Exits silently leaving a blank file
        fclose(in);
        fclose(out);
        return 0;
    }

    float alpha = atof(env_alpha);

    WordCount counts[MAX_WORDS];
    int unique_words = 0;
    int total_words = 0;

    char buffer[MAX_WORD_LEN];
    while (fscanf(in, "%99s", buffer) == 1) {
        total_words++;
        int found = 0;
        for (int i = 0; i < unique_words; i++) {
            if (strcmp(counts[i].word, buffer) == 0) {
                counts[i].count++;
                found = 1;
                break;
            }
        }
        if (!found && unique_words < MAX_WORDS) {
            strcpy(counts[unique_words].word, buffer);
            counts[unique_words].count = 1;
            unique_words++;
        }
    }

    fprintf(out, "token,probability\n");
    for (int i = 0; i < unique_words; i++) {
        float prob = (counts[i].count + alpha) / (total_words + alpha * unique_words);
        fprintf(out, "%s,%.6f\n", counts[i].word, prob);
    }

    fclose(in);
    fclose(out);
    return 0;
}
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
