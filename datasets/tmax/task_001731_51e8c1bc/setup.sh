#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/legacy

    cat << 'EOF' > /home/user/legacy/checksum.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    char *str = argv[1];
    int sum = 0;

    #ifdef ALT_POLY
    sum = 42;
    #endif

    for(int i = 0; i < strlen(str); i++) {
        sum = (sum + str[i]) % 256;
    }
    printf("%d\n", sum);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/legacy/Makefile
checksum_bin: checksum.c
    gcc -o checksum_bin checksum.c
EOF

    cat << 'EOF' > /home/user/legacy/validator.py
import subprocess
import sys

def get_checksum(text):
    p = subprocess.Popen(['./checksum_bin', text], stdout=subprocess.PIPE)
    out, _ = p.communicate()
    return int(out.strip())

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print "Usage: validator.py <text>"
        sys.exit(1)
    text = sys.argv[1]
    base_sum = get_checksum(text)

    total = 0
    for i in xrange(base_sum):
        total += i
    print "Result:", total
EOF
    chmod +x /home/user/legacy/validator.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
