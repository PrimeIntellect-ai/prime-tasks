#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/collatz_ext
    cd /home/user/collatz_ext

    cat << 'EOF' > collatz.c
int collatz_length(long long n) {
    if (n <= 0) return -1;
    int count = 0;
    // BUG: should be n > 1, n > 0 causes infinite loop or wrong logic if it hits 1
    while (n > 0) { 
        if (n % 2 == 0) {
            n = n / 2;
        } else {
            n = 3 * n + 1;
        }
        count++;
    }
    return count;
}
EOF

    cat << 'EOF' > Makefile
CC=gcc
CFLAGS=-Wall -Wextra -O2

all: libcollatz.so

libcollatz.so: collatz.c
	$(CC) $(CFLAGS) -o libcollatz.so collatz.c

clean:
	rm -f *.so *.o
EOF

    cat << 'EOF' > test_collatz.py
import ctypes
import os
import pytest

def test_collatz():
    lib_path = os.path.abspath('./libcollatz.so')
    assert os.path.exists(lib_path), "Shared library not found!"

    lib = ctypes.CDLL(lib_path)
    lib.collatz_length.argtypes = [ctypes.c_longlong]
    lib.collatz_length.restype = ctypes.c_int

    assert lib.collatz_length(1) == 0
    assert lib.collatz_length(2) == 1
    assert lib.collatz_length(12) == 9
    assert lib.collatz_length(27) == 111
EOF

    cat << 'EOF' > run_tests.py
import subprocess
import sys

def main():
    print("Building project...")
    make_proc = subprocess.run(['make', 'clean', 'all'], capture_output=True, text=True)
    if make_proc.returncode != 0:
        print("Build failed:\n", make_proc.stderr)
        sys.exit(1)

    print("Running tests...")
    test_proc = subprocess.run(['python3', '-m', 'pytest', 'test_collatz.py'], capture_output=True, text=True)
    if test_proc.returncode != 0:
        print("Tests failed:\n", test_proc.stdout)
        sys.exit(1)

    print("All tests passed!")
    sys.exit(0)

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/collatz_ext
    chmod -R 777 /home/user
