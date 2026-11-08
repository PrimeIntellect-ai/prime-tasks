#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make g++ espeak-ng ffmpeg
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil
    mkdir -p /home/user/ws_server

    # Generate audio
    espeak-ng -w /app/bug_report.wav "To fix the vulnerability, the sanitizer must reject any payload that contains a null byte. It must also reject any payload containing the exact string 'exec(' and any payload containing the HTML script tag, case-insensitive, so even angle bracket capital S C R I P T angle bracket must be rejected. Everything else is clean."

    # Clean corpus
    echo '{"type":"message", "data":"hello world"}' > /app/corpus/clean/file1.txt
    echo '<p>Just a normal paragraph</p>' > /app/corpus/clean/file2.txt
    echo 'exec_function_call()' > /app/corpus/clean/file3.txt
    echo 'execute(' > /app/corpus/clean/file4.txt
    echo 'Normal text message' > /app/corpus/clean/file5.txt

    # Evil corpus
    printf 'hello\x00world' > /app/corpus/evil/file1.txt
    echo 'system("exec(rm -rf /)");' > /app/corpus/evil/file2.txt
    echo '<ScRipt>alert(1)</script>' > /app/corpus/evil/file3.txt
    echo 'some text <SCRIPT src="evil.js"></SCRIPT>' > /app/corpus/evil/file4.txt
    printf 'null\x00byte inside' > /app/corpus/evil/file5.txt

    # Broken C++ code
    cat << 'EOF' > /home/user/ws_server/sanitizer.cpp
#include <iostream>
// Missing headers

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    std::string filepath = argv[1];

    // TODO: read file and sanitize

    // Broken syntax
    std::cout << "File: " + filepath

    return 0;
}
EOF

    # Makefile
    cat << 'EOF' > /home/user/ws_server/Makefile
CXX = g++
CXXFLAGS = -std=c++11 -O2

all: sanitize

sanitize: sanitizer.cpp
	$(CXX) $(CXXFLAGS) -o sanitize sanitizer.cpp

clean:
	rm -f sanitize
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
