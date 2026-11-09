#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/project
    cd /home/user/project

    cat << 'EOF' > main.c
#include <stdio.h>
extern int advanced_calculate(int a, int b);
int main() {
    printf("Result: %d\n", advanced_calculate(5, 7));
    return 0;
}
EOF

    cat << 'EOF' > libmathops_v1.2.0.c
int basic_calculate(int a, int b) { return a + b; }
EOF

    cat << 'EOF' > libmathops_v1.10.0-beta.c
int basic_calculate(int a, int b) { return a + b; }
int advanced_calculate(int a, int b) { return a * b - 1; } // beta has a bug
EOF

    cat << 'EOF' > libmathops_v1.10.0.c
int basic_calculate(int a, int b) { return a + b; }
int advanced_calculate(int a, int b) { return a * b; } // stable
EOF

    cat << 'EOF' > deps.symmap
VERSION 1.2.0
STRONG basic_calculate

VERSION 1.10.0-beta
STRONG basic_calculate
WEAK advanced_calculate

VERSION 1.10.0
STRONG basic_calculate
STRONG advanced_calculate
EOF

    cat << 'EOF' > semver_utils.py
def compare_versions(v1, v2):
    # BUG: Naive string comparison
    if v1 < v2:
        return -1
    elif v1 > v2:
        return 1
    return 0
EOF

    cat << 'EOF' > sym_emulator.py
class SymbolResolver:
    def __init__(self):
        self.symbols = {}

    def parse_and_resolve(self, filepath, target_version):
        current_version = None
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                if not line: continue
                parts = line.split()
                if parts[0] == 'VERSION':
                    current_version = parts[1]
                elif current_version == target_version:
                    sym_type, sym_name = parts[0], parts[1]
                    state = self.symbols.get(sym_name, 'UNRESOLVED')

                    if state == 'UNRESOLVED':
                        if sym_type == 'WEAK':
                            self.symbols[sym_name] = 'WEAK_RESOLVED'
                        elif sym_type == 'STRONG':
                            self.symbols[sym_name] = 'STRONG_RESOLVED'
                    elif state == 'WEAK_RESOLVED':
                        # BUG: Missing transition to STRONG_RESOLVED
                        pass
                    elif state == 'STRONG_RESOLVED':
                        if sym_type == 'STRONG':
                            raise Exception(f"Multiple definition of {sym_name}")

        return self.symbols
EOF

    cat << 'EOF' > build.py
import os
import subprocess
import glob
from semver_utils import compare_versions
from sym_emulator import SymbolResolver

def main():
    # Find all library versions
    lib_files = glob.glob("libmathops_v*.c")
    versions = [f.replace('libmathops_v', '').replace('.c', '') for f in lib_files]

    # Exclude betas to find the latest stable
    stables = [v for v in versions if '-' not in v]

    # Sort to find the max stable version
    latest_version = stables[0]
    for v in stables[1:]:
        if compare_versions(v, latest_version) == 1:
            latest_version = v

    if latest_version != "1.10.0":
        print(f"Error: Selected wrong version: {latest_version}")
        exit(1)

    # Emulate symbol resolution for the target version
    resolver = SymbolResolver()
    symbols = resolver.parse_and_resolve('deps.symmap', latest_version)

    if symbols.get('advanced_calculate') != 'STRONG_RESOLVED':
        print(f"Linker Error: advanced_calculate is not STRONG_RESOLVED. Current state: {symbols.get('advanced_calculate')}")
        exit(1)

    print(f"Building against libmathops_v{latest_version}.c")

    subprocess.run(["gcc", "-shared", "-fPIC", "-o", "libmathops.so", f"libmathops_v{latest_version}.c"], check=True)
    subprocess.run(["gcc", "-o", "app", "main.c", "-L.", "-lmathops"], check=True)
    print("Build successful.")

if __name__ == "__main__":
    main()
EOF
    chmod +x build.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
