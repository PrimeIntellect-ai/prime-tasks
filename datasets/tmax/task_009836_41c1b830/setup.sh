#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gcc-aarch64-linux-gnu
    pip3 install pytest

    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/project/fast_math.c
int multiply(int a, int b) {
    return a * b;
}
EOF

    cat << 'EOF' > /home/user/project/builder.py
import subprocess
import os

def build_target(arch, source_file):
    compiler = 'gcc'
    if arch == 'aarch64':
        compiler = 'aarch64-linux-gnu-gcc'

    output_file = source_file.replace('.c', '.s')

    # We only generate assembly code (-S) to allow assembly-level analysis
    cmd = [compiler, '-S', '-O2', source_file, '-o', output_file]
    if arch == 'x86_64':
        cmd.insert(1, '-m64')

    subprocess.run(cmd, check=True)
    return output_file
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/project
    chmod -R 777 /home/user
