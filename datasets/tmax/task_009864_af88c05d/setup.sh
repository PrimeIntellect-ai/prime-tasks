#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/rate_limiter
    cd /home/user/rate_limiter

    cat << 'EOF' > main.cpp
#include <iostream>
#include <fstream>
#include <string>
#include "rate_limiter.h"

bool validate_request(const std::string& payload);

int main(int argc, char** argv) {
    if (argc != 3) return 1;
    std::ifstream in(argv[1]);
    std::ofstream out(argv[2]);
    std::string user, payload;
    int timestamp;

    while (in >> user >> timestamp >> payload) {
        if (!validate_request(payload)) {
            out << "INVALID\n";
        } else if (is_rate_limited(user, timestamp)) {
            out << "LIMITED\n";
        } else {
            out << "ACCEPTED\n";
        }
    }
    return 0;
}
EOF

    cat << 'EOF' > rate_limiter.h
#ifndef RATE_LIMITER_H
#define RATE_LIMITER_H
#include <string>

bool is_rate_limited(const std::string& user_id, int timestamp);

#endif
EOF

    cat << 'EOF' > rate_limiter.cpp
#include "rate_limiter.h"
#include <map>

bool is_rate_limited(const std::string& user_id, int timestamp) {
    static std::map<std::string, int*> user_history;
    static std::map<std::string, int> user_counts;

    if (user_history.find(user_id) == user_history.end()) {
        user_history[user_id] = new int[3]; // limit 3 requests per 10s
        user_counts[user_id] = 0;
    }

    int count = user_counts[user_id];
    int* history = user_history[user_id];

    // BUG: count <= 3 allows writing to history[3] which is out of bounds for an array of size 3.
    // To fix, it should be count < 3.
    if (count <= 3) {
        history[count] = timestamp;
        user_counts[user_id]++;
        return false;
    } else {
        if (timestamp - history[0] < 10) {
            return true;
        } else {
            history[0] = history[1];
            history[1] = history[2];
            history[2] = timestamp;
            return false;
        }
    }
}
EOF

    cat << 'EOF' > validator.py
def validate_request(payload: str) -> bool:
    # Rule 1: length between 10 and 50 inclusive
    if len(payload) < 10 or len(payload) > 50:
        return False
    # Rule 2: must start with "REQ-"
    if not payload.startswith("REQ-"):
        return False
    # Rule 3: must contain at least one digit
    if not any(c.isdigit() for c in payload):
        return False
    return True
EOF

    cat << 'EOF' > requests.txt
user1 100 REQ-12345678
user1 101 REQ-87654321
user1 102 REQ-00000000
user1 103 REQ-11111111
user2 104 BAD-12345678
user2 105 REQ-abcd5efghi
user1 112 REQ-99999999
user3 200 REQ-short
user3 201 REQ-thisisaverylongpayloadthatiswayoverfiftycharacterslong1
user3 202 REQ-nodigitsatall
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
