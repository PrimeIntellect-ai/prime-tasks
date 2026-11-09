#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc locales binutils
    pip3 install pytest

    # Generate UTF-8 locale for C program wide char support
    locale-gen en_US.UTF-8
    update-locale LANG=en_US.UTF-8

    mkdir -p /app

    cat << 'EOF' > /tmp/scorer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <locale.h>
#include <wchar.h>

void process_line(char *line) {
    line[strcspn(line, "\r\n")] = 0;

    char *key = strtok(line, ",");
    char *eng = strtok(NULL, ",");
    char *fr = strtok(NULL, ",");
    char *es = strtok(NULL, ",");
    char *de = strtok(NULL, ",");
    char *ja = strtok(NULL, ",");

    if (!ja) return;

    char *targets[] = {fr, es, de, ja};
    char *langs[] = {"fr", "es", "de", "ja"};

    wchar_t w_eng[2048];
    mbstowcs(w_eng, eng, 2048);
    int len_eng = wcslen(w_eng);

    for (int i=0; i<4; i++) {
        wchar_t w_tgt[2048];
        mbstowcs(w_tgt, targets[i], 2048);
        int len_tgt = wcslen(w_tgt);

        int penalty = 50 * abs(len_eng - len_tgt);
        int char_diff = 0;
        int min_len = len_eng < len_tgt ? len_eng : len_tgt;
        for(int j=0; j<min_len; j++) {
            char_diff += abs((int)w_eng[j] - (int)w_tgt[j]);
        }
        int total = penalty + char_diff;
        printf("[LANG-%s] %s => \"%s\" | DIST:%d\n", langs[i], key, targets[i], total);
    }
}

int main() {
    setlocale(LC_ALL, "en_US.UTF-8");
    char *line = NULL;
    size_t len = 0;
    while (getline(&line, &len, stdin) != -1) {
        process_line(line);
    }
    free(line);
    return 0;
}
EOF

    gcc -O2 /tmp/scorer.c -o /app/legacy_loc_scorer
    strip /app/legacy_loc_scorer
    rm /tmp/scorer.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
