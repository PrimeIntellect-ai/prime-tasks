#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make gawk
    pip3 install pytest

    mkdir -p /app/decoder_src

    cat << 'EOF' > /app/decoder_src/decoder.c
#include <stdio.h>
int main(int argc, char **argv) {
    printf("Extracted acoustic parameter K: 4.25\n");
    return 0;
}
EOF

    cat << 'EOF' > /app/decoder_src/Makefile
all:
	gcc decoder.c -o decoder
EOF

    touch /app/signal.wav

    cat << 'EOF' > /tmp/generate_data.py
import random

K = 4.25
random.seed(42)
with open('/app/guesses.txt', 'w') as fg, open('/tmp/truth_roots.txt', 'w') as ft:
    for _ in range(1000):
        guess = random.uniform(0.1, 5.0)
        fg.write(f"{guess}\n")
        x = guess
        for _ in range(100):
            deriv = 3 * x**2 - K
            if deriv == 0:
                x = float('nan')
                break
            x = x - (x**3 - K * x + 1) / deriv
        if str(x) == 'nan':
            ft.write("NaN\n")
        else:
            ft.write(f"{x}\n")
EOF

    python3 /tmp/generate_data.py

    cat << 'EOF' > /tmp/verify.awk
BEGIN { max_err = 0; count = 0 }
{
    agent = $1;
    getline ref < "/tmp/truth_roots.txt";
    if (agent == "NaN" || ref == "NaN") {
        if (agent != ref) err = 999;
        else err = 0;
    } else {
        err = agent - ref;
        if (err < 0) err = -err;
    }
    if (err > max_err) max_err = err;
    count++;
}
END {
    if (count != 1000) {
        print "Error: Expected 1000 lines, got " count > "/dev/stderr";
        print 999;
    } else {
        print max_err;
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
