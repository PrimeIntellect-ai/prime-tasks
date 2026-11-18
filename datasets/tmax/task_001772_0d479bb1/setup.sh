#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/test_env/src /home/user/test_env/include /home/user/test_env/test /home/user/test_env/lib /home/user/test_env/bin
    cd /home/user/test_env

    cat << 'EOF' > include/libdata.h
#ifndef LIBDATA_H
#define LIBDATA_H

int process_data(const char* filename);

#endif
EOF

    cat << 'EOF' > src/libdata.c
#include <stdio.h>
#include <stdlib.h>
#include "libdata.h"

int process_data(const char* filename) {
    FILE* f = fopen(filename, "r");
    if (!f) return -1;
    int sum = 0, val;
    while (fscanf(f, "%d", &val) == 1) {
        sum += val;
    }
    fclose(f);
    return sum;
}
EOF

    cat << 'EOF' > test/runner.cpp
#include <iostream>
#include "libdata.h"

int main() {
    int result = process_data("data.txt");
    if (result == -1) {
        std::cerr << "Failed to process data." << std::endl;
        return 1;
    }
    std::cout << "Data sum: " << result << std::endl;
    return 0;
}
EOF

    cat << 'EOF' > Makefile
all: runner

libdata.so: src/libdata.c
	gcc -shared -o lib/libdata.so src/libdata.c -Iinclude

runner: test/runner.cpp libdata.so
	g++ -o bin/runner test/runner.cpp -Iinclude -Llib -ldata

clean:
	rm -rf lib/* bin/*
EOF

    cat << 'EOF' > data.txt
15
25
40
20
100
EOF

    chown -R user:user /home/user/test_env
    chmod -R 777 /home/user
