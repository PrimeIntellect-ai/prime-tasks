#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/validator.h
#ifndef VALIDATOR_H
#define VALIDATOR_H

#include <string>

class WsValidator {
    long long last_timestamp = 0;
public:
    bool validate_payload(const std::string& payload);
    bool check_rate_limit(long long timestamp_ms);
};

#endif
EOF

    cat << 'EOF' > /home/user/validator.cpp
#include "validator.h"
#include <regex>

bool WsValidator::validate_payload(const std::string& payload) {
    // BUG: Missing literal quotes around the data value in regex
    std::regex r(R"(\{"id": \d+, "data": [a-zA-Z]+\})");
    return std::regex_match(payload, r);
}

bool WsValidator::check_rate_limit(long long timestamp_ms) {
    // BUG: Wrong threshold (10 instead of 100)
    if (timestamp_ms - last_timestamp >= 10) { 
        last_timestamp = timestamp_ms;
        return true;
    }
    return false;
}
EOF

    cat << 'EOF' > /home/user/test_validator.cpp
#include "validator.h"
#include <iostream>
#include <cassert>

int main() {
    WsValidator v;

    // Test 1: Serialization/Validation
    assert(v.validate_payload(R"({"id": 123, "data": "hello"})") == true);
    assert(v.validate_payload(R"({"id": 123, "data": 456})") == false);
    assert(v.validate_payload(R"({"id": "abc", "data": "hello"})") == false);

    // Test 2: Rate Limiting (100ms)
    assert(v.check_rate_limit(1000) == true);
    assert(v.check_rate_limit(1050) == false); 
    assert(v.check_rate_limit(1100) == true);  
    assert(v.check_rate_limit(1150) == false);
    assert(v.check_rate_limit(1200) == true);

    std::cout << "ALL TESTS PASSED" << std::endl;
    return 0;
}
EOF

    chmod -R 777 /home/user
