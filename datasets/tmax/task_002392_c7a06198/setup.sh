#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ make
    pip3 install pytest

    # Create directories
    mkdir -p /app/fast-url-router-1.0.0
    mkdir -p /opt/oracle

    # Create validator.c
    cat << 'EOF' > /app/fast-url-router-1.0.0/validator.c
#include "validator.h"
#include <stdint.h>
#include <stddef.h>

uint32_t calculate_checksum(const char* data, size_t len) {
    uint32_t hash = 5381;
    for (size_t i = 0; i < len; ++i) {
        hash = ((hash << 5) + hash) + data[i]; /* hash * 33 + c */
    }
    return hash;
}
EOF

    # Create validator.h (missing extern "C")
    cat << 'EOF' > /app/fast-url-router-1.0.0/validator.h
#ifndef VALIDATOR_H
#define VALIDATOR_H

#include <stdint.h>
#include <stddef.h>

uint32_t calculate_checksum(const char* data, size_t len);

#endif
EOF

    # Create router.cpp (with logical bug)
    cat << 'EOF' > /app/fast-url-router-1.0.0/router.cpp
#include <iostream>
#include <string>
#include <vector>
#include "validator.h"

using namespace std;

string base64_decode(const string &in) {
    string out;
    vector<int> T(256, -1);
    for (int i=0; i<64; i++) T["ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"[i]] = i; 

    int val=0, valb=-8;
    for (unsigned char c : in) {
        if (T[c] == -1) break;
        val = (val<<6) + T[c];
        valb += 6;
        if (valb>=0) {
            out.push_back(char((val>>valb)&0xFF));
            valb-=8;
        }
    }
    return out;
}

int main(int argc, char** argv) {
    if (argc != 2) {
        cerr << "Usage: " << argv[0] << " <url>" << endl;
        return 1;
    }
    string url = argv[1];

    size_t q_pos = url.find('?');
    string path = url.substr(0, q_pos);
    cout << "Path: " << path << endl;

    if (q_pos != string::npos) {
        string query = url.substr(q_pos + 1);
        size_t p_pos = query.find("payload=");
        if (p_pos != string::npos) {
            size_t start = p_pos + 8;
            size_t end = query.find('&', start);
            if (end == string::npos) {
                end = query.length() - 1; // Bug: off-by-one
            }
            string payload = query.substr(start, end - start);
            string decoded = base64_decode(payload);
            cout << "Decoded Payload: " << decoded << endl;
            uint32_t checksum = calculate_checksum(decoded.c_str(), decoded.length());
            cout << "Checksum: " << checksum << endl;
        }
    }
    return 0;
}
EOF

    # Create Makefile (with missing link flags)
    cat << 'EOF' > /app/fast-url-router-1.0.0/Makefile
all: libvalidator.so fast_router

libvalidator.so: validator.c
	gcc -fPIC -shared -o libvalidator.so validator.c

fast_router: router.cpp
	g++ -o fast_router router.cpp

clean:
	rm -f *.so fast_router
EOF

    # Create Oracle source
    cat << 'EOF' > /opt/oracle/oracle.cpp
#include <iostream>
#include <string>
#include <vector>
#include <stdint.h>
#include <stddef.h>

using namespace std;

uint32_t calculate_checksum(const char* data, size_t len) {
    uint32_t hash = 5381;
    for (size_t i = 0; i < len; ++i) {
        hash = ((hash << 5) + hash) + data[i];
    }
    return hash;
}

string base64_decode(const string &in) {
    string out;
    vector<int> T(256, -1);
    for (int i=0; i<64; i++) T["ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"[i]] = i; 

    int val=0, valb=-8;
    for (unsigned char c : in) {
        if (T[c] == -1) break;
        val = (val<<6) + T[c];
        valb += 6;
        if (valb>=0) {
            out.push_back(char((val>>valb)&0xFF));
            valb-=8;
        }
    }
    return out;
}

int main(int argc, char** argv) {
    if (argc != 2) {
        cerr << "Usage: " << argv[0] << " <url>" << endl;
        return 1;
    }
    string url = argv[1];

    size_t q_pos = url.find('?');
    string path = url.substr(0, q_pos);
    cout << "Path: " << path << endl;

    if (q_pos != string::npos) {
        string query = url.substr(q_pos + 1);
        size_t p_pos = query.find("payload=");
        if (p_pos != string::npos) {
            size_t start = p_pos + 8;
            size_t end = query.find('&', start);
            if (end == string::npos) {
                end = query.length(); // Fixed
            }
            string payload = query.substr(start, end - start);
            string decoded = base64_decode(payload);
            cout << "Decoded Payload: " << decoded << endl;
            uint32_t checksum = calculate_checksum(decoded.c_str(), decoded.length());
            cout << "Checksum: " << checksum << endl;
        }
    }
    return 0;
}
EOF

    # Compile Oracle
    g++ -o /opt/oracle/fast_router_oracle /opt/oracle/oracle.cpp
    chmod +x /opt/oracle/fast_router_oracle

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
