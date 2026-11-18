#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest flask fastapi uvicorn requests

    mkdir -p /app/fast-eval/c_src

    cat << 'EOF' > /app/fast-eval/fast_eval.py
import ctypes
import os

lib_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'libfasteval.so')
_lib = ctypes.CDLL(lib_path)

_lib.compute.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_int]
_lib.compute.restype = ctypes.c_int

def compute(op: str, a: int, b: int) -> int:
    return _lib.compute(op.encode('utf-8'), a, b)
EOF

    cat << 'EOF' > /app/fast-eval/setup.py
import os
import subprocess
import shutil
from setuptools import setup
from setuptools.command.build_py import build_py

class CustomBuild(build_py):
    def run(self):
        c_src_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'c_src')
        subprocess.check_call(['make'], cwd=c_src_dir)
        if not os.path.exists(os.path.join(c_src_dir, 'libfasteval.so')):
            raise RuntimeError("libfasteval.so was not built!")
        super().run()
        shutil.copy(os.path.join(c_src_dir, 'libfasteval.so'), os.path.join(self.build_lib, 'libfasteval.so'))

setup(
    name='fast-eval',
    version='1.0.0',
    py_modules=['fast_eval'],
    cmdclass={'build_py': CustomBuild},
)
EOF

    cat << 'EOF' > /app/fast-eval/c_src/fast_eval.c
#include <string.h>

int compute(const char* op, int a, int b) {
    if (strcmp(op, "ADD") == 0) return a + b;
    if (strcmp(op, "SUB") == 0) return a - b;
    if (strcmp(op, "MUL") == 0) return a * b;
    return 0;
}
EOF

    cat << 'EOF' > /app/fast-eval/c_src/Makefile
CC=gcc
CFLAGS=-O2

all: libfastevel.so

libfastevel.so: fast_eval.c
	$(CC) $(CFLAGS) -shared -o libfastevel.so fast_eval.c

clean:
	rm -f *.so
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
