#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app
    cd /home/user/app

    # Create broken Makefile (using spaces instead of tabs)
    cat << 'EOF' > Makefile
helper_bin: helper.c
    gcc helper.c -o helper_bin
EOF

    # Create helper.c
    cat << 'EOF' > helper.c
#include <stdio.h>
#include <math.h>

int main(int argc, char **argv) {
    double val = sqrt(16.0);
    printf("Helper output: %d\n", (int)val);
    return 0;
}
EOF

    # Create Python 2 script
    cat << 'EOF' > process.py
import sys
import subprocess
import yaml

def process():
    print "Status: 200 OK"
    print "Content-Type: text/plain\n"
    data = yaml.load("{status: success}")
    out = subprocess.check_output(["./helper_bin"])
    print "Data: " + data['status']
    print "System: " + out.decode('utf-8').strip()

if __name__ == "__main__":
    process()
EOF

    chmod -R 777 /home/user
