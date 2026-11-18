#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /home/user/sysdebug
    cd /home/user/sysdebug

    cat << 'EOF' > gamma.c
extern int fetch_config_value(void);
int g() { return fetch_config_value() + 1; }
EOF

    cat << 'EOF' > beta.c
extern int g(void);
int b() { return g() * 2; }
EOF

    cat << 'EOF' > alpha.c
extern int b(void);
int a() { return b() + 3; }
EOF

    gcc -shared -fPIC -o libgamma.so gamma.c
    gcc -shared -fPIC -L. -lgamma -o libbeta.so beta.c
    gcc -shared -fPIC -L. -lbeta -o libalpha.so alpha.c

    cat << 'EOF' > app.py
import ctypes
import sys
import os

def main():
    try:
        lib = ctypes.CDLL("./libalpha.so")
        res = lib.a()
        with open("result.txt", "w") as f:
            f.write(f"Success: {res}")
        print("Done.")
    except Exception as e:
        print(f"Failed to load or execute: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

    rm gamma.c beta.c alpha.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
