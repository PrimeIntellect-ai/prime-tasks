#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc > 1) {
        long long score = 0;
        char *s = argv[1];
        for (int i = 0; s[i] != '\0'; i++) {
            int val = (int)s[i];
            if (val % 2 == 0) {
                score = (score + val) * 2;
            } else {
                score = (score - val) * 3;
            }
            score = score % 10007;
            if (score < 0) {
                score += 10007;
            }
        }
        printf("%lld\n", score);
    }
    return 0;
}
EOF
    gcc -O2 /app/oracle.c -o /app/oracle_bin
    strip /app/oracle_bin
    rm /app/oracle.c

    mkdir -p /home/user/legacy
    cat << 'EOF' > /home/user/legacy/requirements.txt
numpy==1.21.0
pandas==1.3.0
scipy==1.7.0
# Fake conflict:
numpy>=1.22.0
EOF

    cat << 'EOF' > /home/user/legacy/scorer.py
import sys
import numpy as np # Useless import to justify requirements

def legacy_score(s, idx=0, current_score=0):
    # Bug 1: Recursion termination is broken (off-by-one or missing)
    # if idx >= len(s): return current_score  <-- missing

    # To prevent immediate crash for setup, let's just make it error out if idx > len(s)*2
    if idx > len(s) * 2:
        return current_score

    try:
        val = ord(s[idx])
    except IndexError:
        # Bug 2: infinite recursion triggers here
        return legacy_score(s, idx, current_score)

    if val % 2 == 0:
        current_score = (current_score + val) * 2
    else:
        current_score = (current_score - val) * 3

    # Bug 3: Statistical anomaly / drift. Modulo is wrong.
    current_score = current_score % 10000

    return legacy_score(s, idx + 1, current_score)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        print(legacy_score(sys.argv[1]))
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
