#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make golang-go wget
    pip3 install pytest

    # Create directories
    mkdir -p /opt/oracle
    mkdir -p /home/user/app/backend
    mkdir -p /home/user/app/gateway

    # Create oracle source and compile
    cat << 'EOF' > /tmp/oracle.cpp
#include <iostream>
#include <string>

std::string base64_encode(const std::string &in) {
    std::string out;
    int val = 0, valb = -6;
    for (unsigned char c : in) {
        val = (val << 8) + c;
        valb += 8;
        while (valb >= 0) {
            out.push_back("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"[(val >> valb) & 0x3F]);
            valb -= 6;
        }
    }
    if (valb > -6) out.push_back("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"[((val << 8) >> (valb + 8)) & 0x3F]);
    while (out.size() % 4) out.push_back('=');
    return out;
}

int main(int argc, char** argv) {
    if (argc >= 3 && std::string(argv[1]) == "--cli") {
        std::string input = argv[2];
        std::string b64 = base64_encode(input);
        for(char &c : b64) {
            c ^= 0x5A;
        }
        std::cout << b64;
    }
    return 0;
}
EOF
    g++ -O3 /tmp/oracle.cpp -o /opt/oracle/backend_server_oracle
    strip /opt/oracle/backend_server_oracle
    rm /tmp/oracle.cpp

    # Create dummy custom crypto library
    cat << 'EOF' > /tmp/crypto_custom.cpp
void dummy_crypto() {}
EOF
    g++ -shared -fPIC -o /usr/lib/libcrypto_custom.so /tmp/crypto_custom.cpp
    rm /tmp/crypto_custom.cpp

    # Create backend files
    cat << 'EOF' > /home/user/app/backend/Makefile
backend_server: main.o algo.o
	g++ -lcrypto_custom main.o algo.o -o backend_server

main.o: main.cpp
	g++ -c main.cpp

algo.o: algo.cpp
	g++ -c algo.cpp
EOF

    cat << 'EOF' > /home/user/app/backend/main.cpp
#include <iostream>
#include <string>

std::string transform_string(const std::string& input);

int main(int argc, char** argv) {
    if (argc >= 3 && std::string(argv[1]) == "--cli") {
        std::cout << transform_string(argv[2]);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/app/backend/algo.cpp
#include <string>

std::string transform_string(const std::string& input) {
    return "";
}
EOF

    # Create gateway files
    cat << 'EOF' > /home/user/app/gateway/config.json
{
  "backend_url": "http://localhost:9999",
  "rate_limit_rps": 0
}
EOF

    cat << 'EOF' > /home/user/app/gateway/main.go
package main

import (
	"encoding/json"
	"io/ioutil"
	"net/http"
	"net/http/httputil"
	"net/url"
)

type Config struct {
	BackendURL   string `json:"backend_url"`
	RateLimitRPS int    `json:"rate_limit_rps"`
}

func main() {
	data, _ := ioutil.ReadFile("config.json")
	var cfg Config
	json.Unmarshal(data, &cfg)

	target, _ := url.Parse(cfg.BackendURL)
	proxy := httputil.NewSingleHostReverseProxy(target)

	http.HandleFunc("/api/v1/process", func(w http.ResponseWriter, r *http.Request) {
		if cfg.RateLimitRPS <= 0 {
			http.Error(w, "Rate limit exceeded", http.StatusTooManyRequests)
			return
		}
		r.URL.Path = "/process"
		proxy.ServeHTTP(w, r)
	})

	http.ListenAndServe(":8080", nil)
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
