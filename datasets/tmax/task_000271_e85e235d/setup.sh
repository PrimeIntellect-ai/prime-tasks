#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make golang
pip3 install pytest

mkdir -p /home/user/smuggler/tests
mkdir -p /home/user/target

# 1. C source for the fuzzer
cat << 'EOF' > /home/user/smuggler/smuggler.c
#include <stdlib.h>
#include <stdio.h>

int init_smuggler() {
    char *mode = getenv("SMUGGLER_MODE");
    if (!mode || mode[0] == '\0') {
        fprintf(stderr, "FATAL: SMUGGLER_MODE env var not set during initialization.\n");
        return 0; // Failure
    }
    return 1; // Success
}

int send_fuzz(const char* host, int port) {
    // Simulate a fast network operation
    return 1;
}
EOF

# 2. Broken Makefile
cat << 'EOF' > /home/user/smuggler/Makefile
CC=gcc
CFLAGS=-O2

all: libsmuggler.so

libsmuggler.so: smuggler.o
	$(CC) -o libsmuggler.so smuggler.o

smuggler.o: smuggler.c
	$(CC) $(CFLAGS) -c smuggler.c -o smuggler.o

clean:
	rm -f *.o *.so
EOF

# 3. Python Bindings
cat << 'EOF' > /home/user/smuggler/smuggler.py
import ctypes
import os

# Load library
lib = ctypes.CDLL(os.path.join(os.path.dirname(__file__), 'libsmuggler.so'))

lib.init_smuggler.restype = ctypes.c_int
lib.send_fuzz.argtypes = [ctypes.c_char_p, ctypes.c_int]
lib.send_fuzz.restype = ctypes.c_int

if not lib.init_smuggler():
    raise RuntimeError("Failed to initialize C library. Check environment variables.")

def send_fuzz(host: str, port: int) -> int:
    return lib.send_fuzz(host.encode('utf-8'), port)
EOF

# 4. Broken Test Suite
cat << 'EOF' > /home/user/smuggler/tests/test_smuggler.py
import unittest
import os

# BUG: Import order causes the init_smuggler to fail because SMUGGLER_MODE is not set yet.
import smuggler

class TestSmuggler(unittest.TestCase):
    def setUp(self):
        os.environ["SMUGGLER_MODE"] = "CI"

    def test_send_fuzz(self):
        res = smuggler.send_fuzz("127.0.0.1", 8080)
        self.assertEqual(res, 1)

if __name__ == '__main__':
    unittest.main()
EOF

# 5. Go Target Server
cat << 'EOF' > /home/user/target/server.go
package main

import (
    "fmt"
    "net/http"
)

func handler(w http.ResponseWriter, r *http.Request) {
    fmt.Fprintln(w, "OK")
}

func main() {
    http.HandleFunc("/", handler)
    http.ListenAndServe("127.0.0.1:8080", nil)
}
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/smuggler /home/user/target
chmod -R 777 /home/user
