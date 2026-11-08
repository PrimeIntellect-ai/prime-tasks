#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc parallel
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /app/sim_scorer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

void count_vowels(const char* str, int* counts, int* len) {
    *len = 0;
    for (int i = 0; i < 5; i++) counts[i] = 0;
    for (int i = 0; str[i] != '\0'; i++) {
        (*len)++;
        char c = tolower(str[i]);
        if (c == 'a') counts[0]++;
        else if (c == 'e') counts[1]++;
        else if (c == 'i') counts[2]++;
        else if (c == 'o') counts[3]++;
        else if (c == 'u') counts[4]++;
    }
}

int main(int argc, char** argv) {
    if (argc != 3) {
        return 1;
    }
    int counts1[5], counts2[5];
    int len1, len2;
    count_vowels(argv[1], counts1, &len1);
    count_vowels(argv[2], counts2, &len2);

    int manhattan = 0;
    for (int i = 0; i < 5; i++) {
        manhattan += abs(counts1[i] - counts2[i]);
    }
    int len_diff = abs(len1 - len2);

    int score = manhattan * 3 + len_diff * 2;
    printf("%d\n", score);
    return 0;
}
EOF

gcc -O3 -o /app/sim_scorer /app/sim_scorer.c
strip /app/sim_scorer
rm /app/sim_scorer.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
