#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++
    pip3 install pytest

    mkdir -p /home/user/app/src
    mkdir -p /home/user/app/bin

    cat << 'EOF' > /home/user/app/src/utils.cpp
#include <iostream>

extern "C" void log_sanitization(const char* msg) {
    // In a real app this would write to a log file, but we just want to test C/C++ linkage
    std::cerr << "LOG: " << msg << "\n";
}
EOF

    cat << 'EOF' > /home/user/app/src/sanitize.c
#include <stdio.h>
#include <string.h>

extern void log_sanitization(const char* msg);

int main(int argc, char** argv) {
    if (argc < 2) return 1;

    // INTENTIONAL BUG: Buffer is too small, causes buffer overflow on long strings
    char buffer[16]; 
    strcpy(buffer, argv[1]);

    log_sanitization("Data processed");
    printf("CLEAN: %s\n", buffer);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/app/processor.py
import subprocess

def sanitize_data(input_string):
    result = subprocess.run(
        ['/home/user/app/bin/sanitize', input_string],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        raise RuntimeError(f"Sanitizer crashed with return code {result.returncode}")

    output = result.stdout.strip()
    if output.startswith("CLEAN: "):
        return output.replace("CLEAN: ", "", 1)
    return output
EOF

    cat << 'EOF' > /home/user/app/test_processor.py
import pytest
from processor import sanitize_data

def test_sanitize_short():
    assert sanitize_data("short") == "short"

def test_sanitize_long():
    long_string = "this_is_a_very_long_string_that_needs_to_be_sanitized_without_crashing_the_backend_service"
    assert sanitize_data(long_string) == long_string
EOF

    chmod +x /home/user/app/src/sanitize.c
    chmod +x /home/user/app/src/utils.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
