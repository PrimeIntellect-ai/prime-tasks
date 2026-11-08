#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/gcd.c
#include <stdio.h>
#include <stdlib.h>

int gcd(int a, int b) {
    while (b != 0) {
        int temp = b;
        b = a % b;
        a = temp;
    }
    return a;
}

int main(int argc, char *argv[]) {
    if (argc != 3) {
        return 1;
    }
    int a = atoi(argv[1]);
    int b = atoi(argv[2]);
    printf("%d\n", gcd(a, b));
    return 0;
}
EOF

    cat << 'EOF' > /home/user/app/math_wrapper.py
import sys
import subprocess
import os

def main():
    if len(sys.argv) != 3:
        sys.exit(1)

    a = sys.argv[1]
    b = sys.argv[2]

    script_dir = os.path.dirname(os.path.abspath(__file__))
    executable = os.path.join(script_dir, "gcd_calc")

    result = subprocess.run([executable, a, b], capture_output=True, text=True)
    if result.returncode == 0:
        print(result.stdout.strip())
    else:
        sys.exit(result.returncode)

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /home/user/app/build.sh
#!/bin/bash
# Broken build script
gcc gcd.c -o gcd_calc_broken
chmox +x gcd_calc
EOF

    chmod +x /home/user/app/build.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
