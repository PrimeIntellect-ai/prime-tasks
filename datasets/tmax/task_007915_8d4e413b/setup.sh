#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest

    mkdir -p /home/user/auth_server

    # Create the new key file
    echo -n "N3wS3cur3K3y9988" > /home/user/new_key.txt

    # Create the secret key object source
    cat << 'EOF' > /home/user/auth_server/secret.cpp
extern const char* SECRET_KEY = "0LDS3cR3T_123456";
EOF

    # Create the vulnerable source code
    cat << 'EOF' > /home/user/auth_server/login_handler.cpp
#include <iostream>
#include <string>
#include <vector>
#include <sstream>
#include <iomanip>
#include <cstdlib>

extern const char* SECRET_KEY;

// Simple Base64 decoder
std::string base64_decode(const std::string &in) {
    std::string out;
    std::vector<int> T(256,-1);
    for(int i=0;i<64;i++) T["ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"[i]] = i; 
    int val=0, valb=-8;
    for(unsigned char c : in) {
        if(T[c] == -1) break;
        val = (val<<6) + T[c];
        valb += 6;
        if(valb>=0) {
            out.push_back(char((val>>valb)&0xFF));
            valb-=8;
        }
    }
    return out;
}

// Custom simple hash function for MAC
std::string compute_signature(const std::string& key, const std::string& data) {
    unsigned int hash = 0;
    std::string input = key + data;
    for(char c : input) {
        hash = (hash * 31) + c;
    }
    std::stringstream ss;
    ss << std::hex << std::setw(8) << std::setfill('0') << hash;
    return ss.str();
}

int main() {
    const char* qs = std::getenv("QUERY_STRING");
    if (!qs) return 1;

    std::string query(qs);
    std::string payload;
    std::string signature;

    size_t p_pos = query.find("payload=");
    size_t s_pos = query.find("&signature=");

    if (p_pos != std::string::npos && s_pos != std::string::npos) {
        payload = query.substr(p_pos + 8, s_pos - (p_pos + 8));
        signature = query.substr(s_pos + 11);
    }

    std::string expected_sig = compute_signature(SECRET_KEY, payload);

    std::cout << "Content-Type: text/plain\r\n";
    if (expected_sig == signature) {
        std::string redirect_url = base64_decode(payload);
        // VULNERABILITY: Open Redirect
        std::cout << "Location: " << redirect_url << "\r\n\r\n";
        std::cout << "Redirecting..." << std::endl;
    } else {
        std::cout << "\r\nInvalid Signature!" << std::endl;
    }

    return 0;
}
EOF

    # Compile the vulnerable CGI
    g++ -O2 -std=c++11 /home/user/auth_server/login_handler.cpp /home/user/auth_server/secret.cpp -o /home/user/auth_server/login_handler.cgi
    strip /home/user/auth_server/login_handler.cgi

    # Cleanup the secret.cpp to hide it
    rm /home/user/auth_server/secret.cpp

    # Create the user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
