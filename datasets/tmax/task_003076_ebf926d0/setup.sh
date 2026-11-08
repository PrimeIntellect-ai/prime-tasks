#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /app/vendored/BackupUtils-1.2.0
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    cat << 'EOF' > /app/vendored/BackupUtils-1.2.0/Makefile
CXX = g++
CXXFLAGS = -std=c++98 -Wall -Wextra -O2
# Agent must change -std=c++98 to -std=c++17

all: libbackuputils.a

encoding.o: encoding.cpp
	$(CXX) $(CXXFLAGS) -c encoding.cpp -o encoding.o

libbackuputils.a: encoding.o
	ar rcs libbackuputils.a encoding.o

clean:
	rm -f *.o *.a
EOF

    cat << 'EOF' > /app/vendored/BackupUtils-1.2.0/encoding.h
#ifndef ENCODING_H
#define ENCODING_H
#include <string>
#include <string_view>

std::string ConvertToUTF8(const std::string& raw_bytes);

#endif
EOF

    cat << 'EOF' > /app/vendored/BackupUtils-1.2.0/encoding.cpp
#include "encoding.h"
#include <sting> // DELIBERATE TYPO: Agent must fix this to <string>
#include <stdexcept>

// Dummy implementation for the scenario that checks basic BOMs
std::string ConvertToUTF8(const std::string& raw_bytes) {
    if (raw_bytes.size() >= 2 && raw_bytes[0] == '\xFF' && raw_bytes[1] == '\xFE') {
        // Mock UTF-16LE to UTF-8 ASCII-only conversion
        std::string out;
        for (size_t i = 2; i < raw_bytes.size(); i += 2) {
            out += raw_bytes[i];
        }
        return out;
    }
    return raw_bytes; // Assume UTF-8 or ISO-8859-1 for this mock
}
EOF

    python3 -c '
import os
with open("/app/corpora/clean/clean1.log", "wb") as f:
    f.write("System booted successfully.".encode("utf-8"))
with open("/app/corpora/clean/clean2.log", "wb") as f:
    f.write(b"\xff\xfe" + "No errors found in backup.".encode("utf-16le"))
with open("/app/corpora/evil/evil1.log", "wb") as f:
    f.write("Error log: ransomware_payload detected.".encode("utf-8"))
with open("/app/corpora/evil/evil2.log", "wb") as f:
    f.write(b"\xff\xfe" + "Warning: RANSOMWARE_PAYLOAD executed.".encode("utf-16le"))
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
