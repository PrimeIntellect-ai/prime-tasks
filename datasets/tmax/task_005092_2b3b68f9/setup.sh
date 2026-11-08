#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ valgrind binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/service
    cd /home/user/service

    # Create the original vulnerable C++ file for the shared library
    cat << 'EOF' > processor.cpp
#include <stdlib.h>

void process_record(const double* data, int size) {
    // Deliberate memory leak of exactly 1024 bytes per call
    void* leaked_buffer = malloc(1024);
    // Simulate some work to prevent optimization
    if (size > 0 && data) {
        ((char*)leaked_buffer)[0] = (char)data[0];
    }
}
EOF

    # Compile the shared library
    g++ -fPIC -shared -o libprocessor.so processor.cpp

    # Remove the source file so the agent cannot see it
    rm processor.cpp

    # Create the incorrect header file (missing 'const')
    cat << 'EOF' > processor.h
#ifndef PROCESSOR_H
#define PROCESSOR_H

// Incorrect signature - missing 'const'
void process_record(double* data, int size);

#endif
EOF

    # Create the main runner script
    cat << 'EOF' > service.cpp
#include "processor.h"

int main() {
    double data[5] = {1.1, 2.2, 3.3, 4.4, 5.5};

    // Attempting to call the function
    process_record(data, 5);

    return 0;
}
EOF

    chown -R user:user /home/user/service
    chmod -R 777 /home/user
