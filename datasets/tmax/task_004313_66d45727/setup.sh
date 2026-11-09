#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest scipy numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/align_score.c
int get_score(const char* s1, const char* s2) {
    int score = 0;
    while(*s1 && *s2) {
        if (*s1 == *s2) score++;
        s1++; s2++;
    }
    return score;
}
EOF

    chmod -R 777 /home/user
