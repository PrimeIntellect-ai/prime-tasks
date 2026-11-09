#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /home/user/libpool
    mkdir -p /home/user/active_libs
    cd /home/user/libpool

    cat << 'EOF' > a1.c
int B_func1();
int A_entry() { return B_func1(); }
EOF

    cat << 'EOF' > a2.c
int B_func2();
int A_entry() { return B_func2(); }
EOF

    cat << 'EOF' > b1.c
int C_func1();
int D_func1();
int B_func1() { return C_func1() + D_func1(); }
EOF

    cat << 'EOF' > b2.c
int C_func2();
int D_func2();
int B_func2() { return C_func2() + D_func2(); }
EOF

    cat << 'EOF' > c1.c
int C_func1() { return 42; }
EOF

    cat << 'EOF' > c2.c
int C_func2() { return 99; }
EOF

    cat << 'EOF' > d1.c
int D_func1() { return 0; }
EOF

    cat << 'EOF' > d2.c
int D_func2() { return 0; }
EOF

    gcc -shared -fPIC a1.c -o libA_v1.so
    gcc -shared -fPIC a2.c -o libA_v2.so
    gcc -shared -fPIC b1.c -o libB_v1.so
    gcc -shared -fPIC b2.c -o libB_v2.so
    gcc -shared -fPIC c1.c -o libC_v1.so
    gcc -shared -fPIC c2.c -o libC_v2.so
    gcc -shared -fPIC d1.c -o libD_v1.so
    gcc -shared -fPIC d2.c -o libD_v2.so
    rm *.c

    cat << 'EOF' > /home/user/e2e_test.py
import ctypes
import sys
import os

try:
    lib = ctypes.CDLL(os.path.join("/home/user/active_libs", "libA.so"), mode=ctypes.RTLD_GLOBAL)
    # Also load the others so symbols resolve
    ctypes.CDLL(os.path.join("/home/user/active_libs", "libB.so"), mode=ctypes.RTLD_GLOBAL)
    ctypes.CDLL(os.path.join("/home/user/active_libs", "libC.so"), mode=ctypes.RTLD_GLOBAL)
    ctypes.CDLL(os.path.join("/home/user/active_libs", "libD.so"), mode=ctypes.RTLD_GLOBAL)

    res = lib.A_entry()
    if res == 42:
        print("Success! Feature works.")
        sys.exit(0)
    else:
        print(f"Failed. Expected 42, got {res}")
        sys.exit(1)
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
EOF
    chmod +x /home/user/e2e_test.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
