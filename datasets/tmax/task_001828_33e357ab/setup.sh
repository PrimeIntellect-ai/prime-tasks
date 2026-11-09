#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /app/bayes_text_filter-1.2.0
    mkdir -p /app/data/corpus/evil
    mkdir -p /app/data/corpus/clean

    cat << 'EOF' > /app/bayes_text_filter-1.2.0/bayes_filter.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    char word[256];
    int score = 0;
    while (fscanf(f, "%255s", word) == 1) {
        if (strstr(word, "viagra") || strstr(word, "hack") || strstr(word, "crypto") || strstr(word, "drop")) {
            score += 20;
        }
    }
    fclose(f);
    printf("%d\n", score);
    return 0;
}
EOF

    cat << 'EOF' > /app/bayes_text_filter-1.2.0/Makefile
all:
    gcc -o bayes_filter bayes_filter.c

clean:
    rm -f bayes_filter
EOF

    cat << 'EOF' > /app/bayes_text_filter-1.2.0/bayes_score.sh
#!/bin/bash
cd "$(dirname "$0")"
./bayes_clf "$1"
EOF
    chmod +x /app/bayes_text_filter-1.2.0/bayes_score.sh

    echo "buy viagra now and hack some crypto" > /app/data/corpus/evil/evil1.txt
    echo "drop table users and get crypto" > /app/data/corpus/evil/evil2.txt
    echo "hello world this is a clean text" > /app/data/corpus/clean/clean1.txt
    echo "good morning everyone" > /app/data/corpus/clean/clean2.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
