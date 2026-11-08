#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make valgrind
    pip3 install pytest

    mkdir -p /home/user/project
    cd /home/user/project

    cat << 'EOF' > processor.h
#ifndef PROCESSOR_H
#define PROCESSOR_H
int process_data(int input);
#endif
EOF

    cat << 'EOF' > processor.c
#include <stdlib.h>
#include "processor.h"

int process_data(int input) {
    int *buffer = (int*)malloc(sizeof(int) * 100);
    for(int i=0; i<100; i++) {
        buffer[i] = input + i;
    }
    int result = buffer[50];
    // LEAK: memory deallocation is missing
    return result;
}
EOF

    cat << 'EOF' > test_processor.py
import unittest
import ctypes
import os

class TestProcessor(unittest.TestCase):
    # Missing setUp fixture

    def test_process(self):
        self.lib.process_data.argtypes = [ctypes.c_int]
        self.lib.process_data.restype = ctypes.c_int
        result = self.lib.process_data(10)
        self.assertEqual(result, 60)

if __name__ == '__main__':
    unittest.main()
EOF

    cat << 'EOF' > Makefile
all:
	gcc -o processor.so processor.c
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
