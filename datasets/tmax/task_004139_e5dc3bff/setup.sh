#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils strace ltrace gawk
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /tmp/seq_scorer.c
#include <stdio.h>
#include <string.h>

int main() {
    char buf[8192];
    if (fgets(buf, sizeof(buf), stdin)) {
        long long sum = 0;
        long long integral_sum = 0;
        for (int i = 0; buf[i] != '\0' && buf[i] != '\n'; i++) {
            int v = 0;
            if (buf[i] == 'A') v = 1;
            else if (buf[i] == 'C') v = 2;
            else if (buf[i] == 'G') v = -1;
            else if (buf[i] == 'T') v = -2;
            sum += v;
            integral_sum += sum;
        }
        printf("%lld\n", integral_sum);
    }
    return 0;
}
EOF
gcc -O2 /tmp/seq_scorer.c -o /app/seq_scorer
strip /app/seq_scorer
chmod +x /app/seq_scorer

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
